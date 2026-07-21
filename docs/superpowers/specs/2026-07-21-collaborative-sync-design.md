# Collaborative Sync — OT Reconciliation Design

## Status

Approved. Ready for implementation.

## Problem

Three P0 and one P1 issues prevent safe multi-device editing:

1. **P0 — Same `baseRevision` for consecutive local ops** — offline edits all get the same
   `_confirmedRevision`. The server treats them as concurrent and transforms the second against
   the first, corrupting positions.

2. **P0 — `syncPending()` discards `remoteOperations`** — the POST response contains remote ops
   but they are thrown away. The device doesn't see remote changes until reopening the note.

3. **P0 — No local rebase when receiving remote ops** — remote ops are applied directly to the
   editor document without transforming against pending local ops. The client and server can
   diverge.

4. **P1 — Sync requests can overlap** — multiple `syncPending()` calls can run concurrently,
   reading and overwriting the same outbox.

## Solution Overview

Replace the naive append-only sync with an OT-aware reconciliation pipeline that treats the
editor document as a projection of the canonical server snapshot plus the local outbox.

### States

| State | Location | Description |
|-------|----------|-------------|
| `confirmedSnapshot` | SQLite (`note_documents`) | Canonical document from server at revision R |
| `outbox` | SQLite (`pending_note_operations`) | Local ops not yet accepted. Each item has `status: pending \| in_flight` |
| `sync_session` | SQLite (`sync_sessions`) | Tracks in-flight batch: `knownRevision`, `operationIds[]`, `startedAt` |
| `visibleDocument` | MutableDocument (in-memory) | `projection(confirmedSnapshot + outbox)` |

### Sync Flow

```
1. Transação SQLite (antes do POST):
   - marca inFlight como status = 'in_flight'
   - insere sync_session(noteId, knownRevision, operationIds)

2. POST /sync(operations, knownRevision)
   → Response { accepted, remoteOperations, canonicalDocument, finalRevision }

3. Transação SQLite (após resposta):
   - remove accepted que pertencem ao `sync_session` atual
   - pendingRemaining = outbox com status = 'pending'
   - rebase(pendingRemaining, remoteOperations)
   - upsertSnapshot(canonicalDocument, finalRevision)
   - updateOutbox(rebasedOps)  — status = 'pending'
   - delete sync_session
```

### App restart with orphan `sync_session`

```
if sync_session exists:
  reenviar POST /sync com mesmos operationIds
  servidor deduplica → devolve accepted
  executa passo 3 normal
else:
  polling / rebuild normal
```

## Detailed Design

### 1. Serial queue per note (P1)

```dart
class _NoteSyncQueue {
  final Map<String, Future<void>> _tails = {};

  Future<T> run<T>(String noteId, Future<T> Function() fn) {
    final previous = _tails[noteId] ?? Future<void>.value();
    final result = previous.then((_) => fn());
    final tail = result.then<void>((_) {}, onError: (_, __) {});
    _tails[noteId] = tail;
    return result.whenComplete(() {
      if (identical(_tails[noteId], tail)) _tails.remove(noteId);
    });
  }
}
```

O serviço mantém uma fila por `noteId`, e o provider passa sync + polling pela
mesma fila. Uma fila única global bloquearia notas independentes sem necessidade.

```dart
ref.onDispose(() {
  disposed = true;
  pollTimer?.cancel();
  unawaited(controller.dispose());
});
```

Além de sync e polling, a gravação do buffer local no outbox precisa respeitar
essa fronteira: uma operação criada durante um POST deve ser persistida como
`pending`, mas nunca incluída no lote `in_flight` já congelado.

The queue lives in `NoteOperationsSyncService` and wraps:
- Snapshot outbox + persist `sync_session`
- POST /sync
- Rebase + persist snapshot + outbox
- Rebuild visible document

### 2. `_localRevision` (speculative baseRevision)

Each pending op receives:

```
baseRevision = confirmedRevision + projectedOutboxIndex
```

Where `projectedOutboxIndex` is the number of operations already projected over
the confirmed snapshot at the time this op is flushed. It includes both
`pending` and `in_flight` operations. Otherwise an edit made during a POST is
calculated against the visible in-flight edits but sent with a revision that
does not include them.

```dart
Future<void> _flushLocalOps() async {
  if (_pendingOps.isEmpty) return;
  final projectedCount = await _syncService.getProjectedOutboxOperationCount(_noteId);
  final ops = List<OperationRequest>.from(_pendingOps);
  _pendingOps.clear();

  for (int i = 0; i < ops.length; i++) {
    final old = ops[i];
    ops[i] = OperationRequest(
      operationId: old.operationId,
      baseRevision: _confirmedRevision + projectedCount + i,
      kind: old.kind,
      blockId: old.blockId,
      payload: old.payload,
    );
  }
  for (final op in ops) {
    await _syncService.enqueueOperation(_noteId, op);
  }
  onLocalOperations?.call(ops);
}
```

### 3. `sync_session` persistence (crash safety)

New SQLite table:

```sql
CREATE TABLE sync_sessions (
  note_id TEXT NOT NULL,
  known_revision INTEGER NOT NULL,
  operation_ids TEXT NOT NULL,  -- JSON array of strings
  started_at TEXT NOT NULL,
  PRIMARY KEY (note_id)
);
```

Before POST, within one SQLite transaction:

```dart
await _dao.runInTransaction(() async {
  await _dao.markInFlight(noteId, operationIds);
  await _dao.upsertSyncSession(SyncSession(
    noteId: noteId,
    knownRevision: knownRevision,
    operationIds: operationIds,
    startedAt: DateTime.now().toUtc(),
  ));
});
```

On success, in a transaction:

```dart
await _dao.deleteAccepted(acceptedIds);
await _dao.upsertNoteDocument(...)  // new snapshot
await _dao.replacePendingOps(noteId, rebasedOps);
await _dao.deleteSyncSession(noteId);
```

On startup:

```dart
final session = await _dao.getSyncSession(noteId);
if (session != null) {
  // Load exactly the persisted in_flight rows listed in session.operationIds.
  // Validate that the set of row IDs equals the session IDs before sending.
  // Re-send the same POST with the original knownRevision and operationIds.
  // Server dedup → returns accepted
  // Then complete the transaction
}
```

### 4. Rebase logic

```dart
Future<SyncResult> syncPending(String noteId) async {
  // Run through serial queue
  return _syncQueue.run(noteId, () async {
    final activeSession = await _dao.getSyncSession(noteId);
    if (activeSession != null) {
      // Recovery always precedes polling or a new batch. It retries the exact
      // persisted in_flight request, then runs the normal response transaction.
      return _resumeSyncSession(noteId, activeSession);
    }

    final ops = await _dao.getPendingOperations(noteId, status: 'pending');
    final inFlightIds = ops.map((o) => o.operationId).toSet();
    if (ops.isEmpty) return SyncResult.empty();

    // 1. Mark in_flight + create session
    await _dao.runInTransaction(() async {
      await _dao.markInFlight(inFlightIds, noteId);
      await _dao.upsertSyncSession(...);
    });

    // 2. POST
    final response = await _api.syncOperations(noteId, buildRequest(ops));

    // 3. Process response (transaction)
    await _dao.runInTransaction(() async {
      // A successful all-or-nothing response must acknowledge exactly the
      // session's IDs. A mismatch is protocol failure: retain the session and
      // do not advance the local snapshot.
      _requireExactAcceptance(inFlightIds, response.accepted);
      await _dao.deleteAccepted(inFlightIds);
      final remaining = await _dao.getPendingOperations(noteId, status: 'pending');

      final rebased = _rebaseOps(remaining, response.remoteOperations);

      await _dao.upsertNoteDocument(...);
      // Replace pending rows so operations transformed to no-op are removed,
      // rather than retried forever.
      await _dao.replacePendingOps(noteId, rebased);
      await _dao.deleteSyncSession(noteId);
    });

    return SyncResult(
      acceptedCount: response.accepted.length,
      remoteOperations: response.remoteOperations,
      finalRevision: response.finalRevision,
      canonicalDocument: response.canonicalDocument,
    );
  });
}
```

#### Rebase: text_delta

Uses `dart_quill_delta`:

```dart
class TransformPair {
  final Delta local;
  final Delta remote;
  TransformPair({required this.local, required this.remote});
}

TransformPair transformTextPair({
  required Delta local,
  required Delta remote,
  required String localKey,   // e.g. "actorId:operationId"
  required String remoteKey,
}) {
  // Priority derived from stable global order.
  // When localKey > remoteKey: local has priority → local's insertions win.
  // When remoteKey > localKey: remote has priority.
  final localHasPriority = localKey.compareTo(remoteKey) > 0;

  // localAfterRemote: applies after "remote" to achieve same effect as "local"
  final localAfterRemote = remote.transform(local, !localHasPriority);
  // remoteAfterLocal: applies after "local" to achieve same effect as "remote"
  final remoteAfterLocal = local.transform(remote, localHasPriority);

  return TransformPair(local: localAfterRemote, remote: remoteAfterLocal);
}
```

#### Rebase: block ops

| Local | Remote | Result |
|-------|--------|--------|
| `create(after:X)` | `delete(X)` | after = null (prepend — product rule) |
| `create(after:X)` | `create(after:X)` | winner = min(opId); loser.afterBlockId = winner.blockId |
| `move(X, after:Y)` | `delete(X)` | cancel move (no-op, X deleted) |
| `move(X, after:Y)` | `delete(Y)` | after = null (prepend) |
| `move(X)` | `move(X)` | last-write-wins (based on opId order) |
| `delete(X)` | `delete(X)` | no-op (already deleted) |
| `set_block_type(X)` | `delete(X)` | cancel (block gone) |
| `set_block_type(X)` | `set_block_type(X)` | surviving op wins (when sent later) |

> **Note**: `create(after:X)` is never cancelled by `delete(X)` — it falls back to prepend.
> Only ops that TARGET block X directly are cancelled by `delete(X)`.

Every block transform returns either a transformed operation or `no-op`. The
reconciliation transaction removes no-ops from the pending outbox. A canceled
operation must never remain eligible for later retries.

#### Rebase: baseRevision recalculation

```dart
for (int i = 0; i < rebasedOps.length; i++) {
  rebasedOps[i].baseRevision = finalRevision + i;
}
```

### 5. Rebuild visible document

```dart
Future<void> rebuildFromSnapshot({
  required Map<String, dynamic> snapshot,
  required List<PendingNoteOperationData>? rebasedOps,
}) async {
  // IME protection: defer rebuild during active IME composition window
  // so the engine doesn't replace the document mid-composition, losing characters.
  // Track via Editor composer's isComposing or a local flag set on
  // RawKeyEvent / TextInput compositionStart / compositionEnd.
  if (_isComposing) {
    _pendingRebuild = RebuildRequest(snapshot: snapshot, ops: rebasedOps);
    return;
  }

  _listening = false;
  try {
    // Clear editor
    for (final node in _document.toList()) {
      _document.removeNode(node.id);
    }
    // Apply canonical blocks
    _applyFullDocument(snapshot);
    // Apply rebased pending ops
    if (rebasedOps != null) {
      for (final op in rebasedOps) {
        _applyOperationRequest(op);
      }
    }
    _buildMirror();
  } finally {
    _listening = true;
  }
}
```

### 6. Server changes

#### `SyncResponse` — add canonical document

```go
type SyncResponse struct {
    Accepted         []AcceptedOperation `json:"accepted"`
    FinalRevision    int64               `json:"finalRevision"`
    RemoteOperations []Operation         `json:"remoteOperations"`
    CanonicalDocument json.RawMessage    `json:"canonicalDocument"`
    ServerTime       time.Time           `json:"serverTime"`
}
```

The `CanonicalDocument` is the canonical snapshot at `FinalRevision` — serialized from the in-memory
`Document` after all operations in the batch are applied.

#### `remoteOperations` limited to `finalRevision`

After commit, query explicitly:

```go
docJSON, _ := json.Marshal(doc)
// commit
remoteOps, _ := repo.GetOperationsRange(ctx, noteID, req.KnownRevision, currentRevision)
```

```sql
WHERE note_id = $1
  AND revision > $2
  AND revision <= $3
ORDER BY revision
```

Then filter out `acceptedOperationIds`.

#### Polling endpoint — consistent read

```sql
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
  SELECT document, revision FROM notes WHERE id = $1;
  -- Bind the revision returned above as $snapshot_revision in this query.
  SELECT * FROM note_operations
  WHERE note_id = $1 AND revision > $2 AND revision <= $snapshot_revision
  ORDER BY revision;
COMMIT;
```

Return: `{ document, revision, operations }`.

#### Server-side transform priority

Currently hardcoded `false`. Change to derive from `(actorId, operationId)`:

```go
func transformPriority(clientActorID, serverActorID uuid.UUID, clientOpID, serverOpID uuid.UUID) bool {
    clientKey := clientActorID.String() + ":" + clientOpID.String()
    serverKey := serverActorID.String() + ":" + serverOpID.String()
    return clientKey > serverKey
}
```

Then:

```go
priority := transformPriority(clientActorID, serverActorID, opID, concurrentOp.OperationID)
clientDelta = serverDelta.Transform(*clientDelta, priority)
```

### 7. Dependencies

- `dart_quill_delta: ^10.8.3` (or compatible) — OT for text_delta operations

### 8. Testing

**Unit tests** (Dart):
- `transformTextPair` convergence (same input, opposite sides → same output)
- `_rebaseOps` with text_delta + block ops
- `rebuildFromSnapshot` — doc state matches projection
- `_flushLocalOps` — baseRevisions are sequential
- block transform rules (create+delete, create+create, move+delete, etc.)

**Unit tests** (Go):
- `GetOperationsRange` boundary
- `transformPriority` determinism
- `SyncResponse.document` matches `finalRevision`

**Integration tests** (required for approval):
- Two offline inserts in the same block → no corruption on sync
- Concurrent sync + edit during request → ops outside `inFlight` are preserved
- Polling with pending outbox → remote ops merged in
- Concurrent `create(after:X)` from two devices → convergent anchor
- `create/move/delete` concurrent → deterministic ordering
- App restart with orphan `sync_session` → no duplicate content
- App restart with persisted outbox → visible document restored
- IME composition + rebuild → no character loss

### Outbox status migration

Add `status TEXT NOT NULL DEFAULT 'pending'` column to `pending_note_operations`.

### New DAO methods

```dart
// SyncSession CRUD
Future<SyncSessionData?> getSyncSession(String noteId);
Future<void> upsertSyncSession(SyncSessionsCompanion session);
Future<void> deleteSyncSession(String noteId);

// Outbox status
Future<void> markInFlight(String noteId, Set<String> operationIds);
Future<List<PendingNoteOperationData>> getPendingOperations(String noteId, {String? status});
Future<int> getProjectedOutboxOperationCount(String noteId); // pending + in_flight
Future<void> replacePendingOps(String noteId, List<PendingNoteOperationData> ops);

// Transaction helper
Future<void> runInTransaction(Future<void> Function() fn);
```

### New Drift table

```dart
class SyncSessions extends Table {
  TextColumn get noteId => text()();
  IntColumn get knownRevision => integer()();
  TextColumn get operationIds => text()(); // JSON array
  TextColumn get startedAt => text()();

  @override
  Set<Column> get primaryKey => {noteId};
}
```

## Open Questions

- `dart_quill_delta` version compatibility with project SDK constraint `>=3.10.0`
- Go `pgx` REPEATABLE READ transaction API (already in use, just verify syntax)

## References

- PRD: Multi-device collaborative editing
- Existing adapter: `lib/features/notes/domain/note_operation_adapter.dart`
- Existing sync service: `lib/core/sync/note_operations_sync_service.dart`
- Server service: `backend/internal/noteoperations/service.go`
- Server validate: `backend/internal/noteoperations/validator.go`
- Server transform: `backend/internal/noteoperations/transformer.go`
- Server operation model: `backend/internal/noteoperations/operation.go`
- Server document model: `backend/internal/noteoperations/document.go`

# Collaborative Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement OT-aware sync reconciliation with `sync_session` durability, serial queue, speculative `baseRevision`, and `canonicalDocument`-based rebuild.

**Architecture:** Server returns `canonicalDocument` in `SyncResponse`. Client persists `sync_session` before POST, rebases remaining pending ops against `remoteOperations`, and rebuilds the visible document from `canonicalDocument + rebasedOutbox`. A per-note serial queue prevents concurrent sync/polling. Transform priority derived from `(actorId, operationId)`.

`clientId` remains a per-installation request identifier. It is **not** the OT
actor. The Flutter rebaser receives the authenticated `actorId` (the same user
UUID the Go service writes as `Operation.ActorID`) for priority comparison.

**Tech Stack:** Go (pgx, go-quilljs-delta), Dart/Flutter (drift, dart_quill_delta, super_editor)

> **Durability invariant:** payload transformation, deletion of the acknowledged
> in-flight rows, persistence of the canonical snapshot, replacement of the
> pending outbox, and deletion of `sync_session` form one SQLite transaction.
> The adapter may rebuild the editor only *after* that transaction commits. It
> must never be responsible for a later durable rebase step.

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `backend/internal/noteoperations/operation.go` | Modify | Add `CanonicalDocument` to `SyncResponse` |
| `backend/internal/noteoperations/service.go` | Modify | Populate `CanonicalDocument`, use `GetOperationsRange`, limit remote ops, `transformPriority` |
| `backend/internal/noteoperations/repository.go` | Modify | Add `GetOperationsRange` + interface |
| `backend/internal/noteoperations/transformer.go` | Modify | Derive priority from `(actorId, operationId)` |
| `backend/internal/noteoperations/service_test.go` | Modify | Tests for new fields + range |
| `backend/internal/noteoperations/transformer_test.go` | Modify | Tests for priority |
| `lib/core/database/tables/sync_sessions.dart` | **Create** | Drift table for `sync_session` |
| `lib/core/database/tables/pending_note_operations.dart` | Modify | Add `status` column |
| `lib/core/database/database.dart` | Modify | Register `SyncSessions` table |
| `lib/core/database/daos/note_operations_dao.dart` | Modify | Add session CRUD, `markInFlight`, `getProjectedOutboxCount`, `replacePendingOps`, `runInTransaction` |
| `pubspec.yaml` | Modify | Add `dart_quill_delta` |
| `lib/core/sync/note_operations_sync_service.dart` | Modify | Add `_NoteSyncQueue`, `sync_session` lifecycle, rebase orchestration |
| `lib/features/notes/domain/note_operation_rebaser.dart` | **Create** | Pure text/block rebase and operation serialization; no editor or DAO access |
| `lib/features/notes/domain/note_operation_adapter.dart` | Modify | Rebuild projection and IME guard; no durable rebase |
| `lib/features/notes/presentation/controllers/note_editor_provider.dart` | Modify | Wire serial queue, call `reconcile()` |
| `lib/features/notes/data/note_operations_api.dart` | Modify | Update `SyncResponse` with `canonicalDocument` |

---

### Task 1: Server — `CanonicalDocument` + `GetOperationsRange`

**Files:**
- Modify: `backend/internal/noteoperations/operation.go:87-92`
- Modify: `backend/internal/noteoperations/service.go:32-163`
- Modify: `backend/internal/noteoperations/repository.go:46-57`

- [ ] **Step 1: Add `CanonicalDocument` to `SyncResponse`**

In `operation.go`, add the field:

```go
type SyncResponse struct {
	Accepted          []AcceptedOperation `json:"accepted"`
	FinalRevision     int64               `json:"finalRevision"`
	RemoteOperations  []Operation         `json:"remoteOperations"`
	CanonicalDocument json.RawMessage     `json:"canonicalDocument"`
	ServerTime        time.Time           `json:"serverTime"`
}
```

- [ ] **Step 2: Add `GetOperationsRange` to `Repository` interface**

In `repository.go`, add to interface:

```go
GetOperationsRange(ctx context.Context, noteID pgtype.UUID, afterRevision int64, upToRevision int64) ([]Operation, error)
```

Add to mock:

```go
func (m *mockRepository) GetOperationsRange(ctx context.Context, noteID pgtype.UUID, afterRevision int64, upToRevision int64) ([]Operation, error) {
	if m.getOperationsRangeFn != nil {
		return m.getOperationsRangeFn(ctx, noteID, afterRevision, upToRevision)
	}
	return nil, nil
}
```

Add implementation:

```go
const getOperationsRangeSQL = `SELECT note_id, revision, operation_id, actor_id, base_revision, kind, block_id, payload, created_at
FROM note_operations WHERE note_id = $1 AND revision > $2 AND revision <= $3 ORDER BY revision`

func (r *repository) GetOperationsRange(ctx context.Context, noteID pgtype.UUID, afterRevision int64, upToRevision int64) ([]Operation, error) {
	rows, err := r.db.Query(ctx, getOperationsRangeSQL, noteID, afterRevision, upToRevision)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ops []Operation
	for rows.Next() {
		var op Operation
		if err := rows.Scan(
			&op.NoteID, &op.Revision, &op.OperationID, &op.ActorID,
			&op.BaseRevision, &op.Kind, &op.BlockID, &op.Payload, &op.CreatedAt,
		); err != nil {
			return nil, err
		}
		ops = append(ops, op)
	}
	return ops, rows.Err()
}
```

- [ ] **Step 3: Update `SyncOperations` to use `GetOperationsRange` + include `CanonicalDocument`**

In `service.go`, after `tx.Commit`:

```go
// After line: if err := tx.Commit(ctx); err != nil { ... }

remoteOps, err := s.repo.GetOperationsRange(ctx, noteID, req.KnownRevision, currentRevision)
if err != nil {
	return SyncResponse{}, fmt.Errorf("fetch remote ops: %w", err)
}

acceptedSet := make(map[string]bool, len(accepted))
for _, a := range accepted {
	acceptedSet[a.OperationID] = true
}

var filteredRemote []Operation
for _, op := range remoteOps {
	if !acceptedSet[opIDToString(op.OperationID)] {
		filteredRemote = append(filteredRemote, op)
	}
}

docJSON, err := json.Marshal(doc)
if err != nil {
	return SyncResponse{}, fmt.Errorf("marshal doc: %w", err)
}

return SyncResponse{
	Accepted:          accepted,
	FinalRevision:     currentRevision,
	RemoteOperations:  filteredRemote,
	CanonicalDocument: docJSON,
	ServerTime:        time.Now().UTC(),
}, nil
```

Remove the old code for `s.repo.GetOperationsSince` and the `import "time"` check.

- [ ] **Step 4: Add `getOperationsRangeFn` to mock struct**

In `service_test.go`:

```go
type mockRepository struct {
	// ... existing fields ...
	getOperationsRangeFn     func(ctx context.Context, noteID pgtype.UUID, afterRevision int64, upToRevision int64) ([]Operation, error)
}
```

Add stub method:

```go
func (m *mockRepository) GetOperationsRange(ctx context.Context, noteID pgtype.UUID, afterRevision int64, upToRevision int64) ([]Operation, error) {
	if m.getOperationsRangeFn != nil {
		return m.getOperationsRangeFn(ctx, noteID, afterRevision, upToRevision)
	}
	return nil, nil
}
```

- [ ] **Step 5: Run existing Go tests to confirm no regression**

```bash
cd backend && go test ./internal/noteoperations/... -count=1
```
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add backend/internal/noteoperations/
git commit -m "feat(server): add CanonicalDocument to SyncResponse + GetOperationsRange"
```

---

### Task 2: Server — `transformPriority` from `(actorId, operationId)`

**Files:**
- Modify: `backend/internal/noteoperations/transformer.go`
- Modify: `backend/internal/noteoperations/service.go`

- [ ] **Step 1: Write failing test**

In `transformer_test.go`:

```go
func TestTransformPriority_Deterministic(t *testing.T) {
	actorA := uuid.MustParse("11111111-1111-1111-1111-111111111111")
	actorB := uuid.MustParse("22222222-2222-2222-2222-222222222222")
	op1 := uuid.MustParse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
	op2 := uuid.MustParse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")

	// Same actor: tiebreak by operationId
	p1 := transformPriority(actorA, actorA, op1, op2)
	p2 := transformPriority(actorA, actorA, op2, op1)
	assert.NotEqual(t, p1, p2, "swapping ops must flip priority")

	// Different actors: tiebreak by actorId first
	p3 := transformPriority(actorA, actorB, op1, op2)
	p4 := transformPriority(actorA, actorB, op1, op2)
	assert.Equal(t, p3, p4, "same inputs must produce same output")
}
```

- [ ] **Step 2: Run to confirm it fails**

```bash
cd backend && go test ./internal/noteoperations/ -run TestTransformPriority_Deterministic -count=1
```
Expected: FAIL with "undefined: transformPriority"

- [ ] **Step 3: Implement `transformPriority`**

In `transformer.go`, add:

```go
func transformPriority(clientActorID, serverActorID uuid.UUID, clientOpID, serverOpID uuid.UUID) bool {
	clientKey := clientActorID.String() + ":" + clientOpID.String()
	serverKey := serverActorID.String() + ":" + serverOpID.String()
	return clientKey > serverKey
}
```

Add `"github.com/google/uuid"` to the import list.

- [ ] **Step 4: Update `validateAndTransform` in `service.go`**

Replace line 198:
```go
clientDelta = serverDelta.Transform(*clientDelta, false)
```
with:
```go
priority := transformPriority(
  clientUUID, // uuid.UUID extracted from authenticated userID
  uuid.UUID(co.ActorID.Bytes),
  opID, // uuid.UUID parsed once from opReq.OperationID
  uuid.UUID(co.OperationID.Bytes),
)
clientDelta = serverDelta.Transform(*clientDelta, priority)
```

Do not pass `pgtype.UUID.Bytes` or string IDs directly to `transformPriority`.
The helper accepts `uuid.UUID` values, and the same tuple ordering must be
replicated by Dart's pure rebaser.

Add `clientUUID uuid.UUID` parameter to `validateAndTransform` signature. Extract `clientUUID` from userID param in `SyncOperations`:

```go
clientUUID := uuid.UUID(userID.Bytes)
```

- [ ] **Step 5: Run tests to confirm pass**

```bash
cd backend && go test ./internal/noteoperations/... -count=1
```
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add backend/internal/noteoperations/
git commit -m "feat(server): derive transform priority from (actorId, operationId)"
```

---

### Task 3: Server — Polling consistent read

**Files:**
- Modify: `backend/internal/noteoperations/service.go`

- [ ] **Step 1: Update `GetOperationsSince` endpoint for REPEATABLE READ**

In `service.go`, modify `GetOperationsSince` method:

```go
func (s *Service) GetOperationsSince(ctx context.Context, noteID pgtype.UUID, userID pgtype.UUID, afterRevision int64) (OperationsListResponse, error) {
	perm, err := s.repo.CheckNotePermission(ctx, noteID, userID)
	if err != nil {
		return OperationsListResponse{}, fmt.Errorf("check permission: %w", err)
	}
	if perm != "owner" && perm != "edit" && perm != "view" {
		return OperationsListResponse{}, ErrNoPermission
	}

	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{
		IsoLevel: pgx.RepeatableRead,
		AccessMode: pgx.ReadOnly,
	})
	if err != nil {
		return OperationsListResponse{}, fmt.Errorf("begin repeatable read tx: %w", err)
	}
	defer tx.Rollback(ctx)

	txRepo := s.repo.WithTx(tx)

	doc, err := txRepo.GetNoteDocument(ctx, noteID)
	if err != nil {
		return OperationsListResponse{}, fmt.Errorf("get document: %w", err)
	}

	ops, err := txRepo.GetOperationsRange(ctx, noteID, afterRevision, doc.Revision)
	if err != nil {
		return OperationsListResponse{}, fmt.Errorf("get operations: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return OperationsListResponse{}, fmt.Errorf("commit tx: %w", err)
	}

	return OperationsListResponse{
		Document:   doc.Document,
		Revision:   doc.Revision,
		Operations: ops,
	}, nil
}
```

- [ ] **Step 2: Add fields to `OperationsListResponse`**

In `operation.go`:

```go
type OperationsListResponse struct {
	Operations []Operation    `json:"operations"`
	Document   json.RawMessage `json:"document,omitempty"`
	Revision   int64          `json:"revision,omitempty"`
}
```

- [ ] **Step 3: Update `repository.go` `GetNoteDocument`**

Add `GetNoteDocument` to the mock struct in `service_test.go` if not already there. It should already exist.

- [ ] **Step 4: Run tests**

```bash
cd backend && go test ./internal/noteoperations/... -count=1
```
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/internal/noteoperations/
git commit -m "feat(server): consistent read for polling endpoint"
```

---

### Task 4: Flutter — `SyncSessions` table + `status` migration

**Files:**
- Create: `lib/core/database/tables/sync_sessions.dart`
- Modify: `lib/core/database/tables/pending_note_operations.dart`
- Modify: `lib/core/database/database.dart`
- Modify: `pubspec.yaml`

- [ ] **Step 1: Create `SyncSessions` drift table**

`lib/core/database/tables/sync_sessions.dart`:

```dart
import 'package:drift/drift.dart';

@DataClassName('SyncSessionData')
class SyncSessions extends Table {
  TextColumn get noteId => text()();
  IntColumn get knownRevision => integer()();
  TextColumn get operationIds => text()(); // JSON array of operation IDs
  TextColumn get startedAt => text()();

  @override
  Set<Column> get primaryKey => {noteId};
}
```

- [ ] **Step 2: Add `status` column to `PendingNoteOperations`**

In `lib/core/database/tables/pending_note_operations.dart`:

```dart
TextColumn get status => text().withDefault(const Constant('pending'))();
```

`AppDatabase` is currently schema version 21 and already has an explicit
`MigrationStrategy`. Extend that existing migration; do not replace it and do
not reset the schema version.

In `AppDatabase`:

```dart
@override
int get schemaVersion => 22;

// Inside the existing migration.onUpgrade callback:
if (from < 22) {
  await m.addColumn(pendingNoteOperations, pendingNoteOperations.status);
  await m.createTable(syncSessions);
}
```

- [ ] **Step 3: Register `SyncSessions` in `database.dart`**

Add import:
```dart
import 'tables/sync_sessions.dart';
```

Add `SyncSessions` to the tables list:
```dart
@DriftDatabase(
  tables: [
    // ... existing ...
    SyncSessions,
  ],
)
```

- [ ] **Step 4: Add `dart_quill_delta` dependency**

In `pubspec.yaml`:
```yaml
  dart_quill_delta: ^10.8.3
```

- [ ] **Step 5: Run build_runner to regenerate drift code**

```bash
cd "C:\Users\rigleyc\projects\supanotes" && dart run build_runner build --delete-conflicting-outputs
```
Expected: Drift generated code compiles without errors.

- [ ] **Step 6: Commit**

```bash
git add lib/core/database/ pubspec.yaml pubspec.lock
git commit -m "feat(db): add sync_sessions table, status column, dart_quill_delta dep"
```

---

### Task 5: Flutter — DAO methods for sync session + outbox

**Files:**
- Modify: `lib/core/database/daos/note_operations_dao.dart`

- [ ] **Step 1: Write tests first in `test/core/database/daos/note_operations_dao_test.dart`**

Create the test file:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:supanotes/core/database/daos/note_operations_dao.dart';

void main() {
  // Integration test with an in-memory database
  // Test: markInFlight, getPendingOperations with filter, replacePendingOps,
  //       getProjectedOutboxCount, sync_session CRUD
}
```

- [ ] **Step 2: Add DAO methods**

In `lib/core/database/daos/note_operations_dao.dart`, add inside the class:

```dart
  // SyncSession CRUD
  Future<SyncSessionData?> getSyncSession(String noteId) {
    return (select(syncSessions)
          ..where((t) => t.noteId.equals(noteId)))
        .getSingleOrNull();
  }

  Future<void> upsertSyncSession(SyncSessionsCompanion session) {
    return into(syncSessions).insert(
      session,
      onConflict: DoUpdate((_) => session),
    );
  }

  Future<void> deleteSyncSession(String noteId) async {
    await (delete(syncSessions)
          ..where((t) => t.noteId.equals(noteId)))
        .go();
  }

  // Outbox status
  Future<void> markInFlight(String noteId, Set<String> operationIds) async {
    await transaction(() async {
      for (final id in operationIds) {
        await (update(pendingNoteOperations)
              ..where((t) => t.operationId.equals(id)))
            .write(
          PendingNoteOperationsCompanion(
            status: const Value('in_flight'),
          ),
        );
      }
    });
  }

  Future<List<PendingNoteOperationData>> getPendingOperations(
    String noteId, {
    String? status,
  }) async {
    final query = select(pendingNoteOperations)
      ..where((t) => t.noteId.equals(noteId))
      ..orderBy([(t) => OrderingTerm(expression: t.ordinal)]);
    if (status != null) {
      query.where((t) => t.status.equals(status));
    }
    return query.get();
  }

  Future<int> getProjectedOutboxOperationCount(String noteId) async {
    final count = await (select(pendingNoteOperations)
          ..where((t) => t.noteId.equals(noteId)))
        .map((row) => row.operationId)
        .get();
    return count.length;
  }

  Future<void> replacePendingOps(
    String noteId,
    List<PendingNoteOperationData> ops,
  ) async {
    await transaction(() async {
      await (delete(pendingNoteOperations)
            ..where((t) => t.noteId.equals(noteId)))
          .go();
      for (int i = 0; i < ops.length; i++) {
        final op = ops[i];
        await into(pendingNoteOperations).insert(
          PendingNoteOperationsCompanion(
            operationId: Value(op.operationId),
            noteId: Value(op.noteId),
            baseRevision: Value(op.baseRevision),
            ordinal: Value(i),
            kind: Value(op.kind),
            blockId: Value(op.blockId),
            payloadJson: Value(op.payloadJson),
            createdAt: Value(op.createdAt),
            status: Value('pending'),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  Future<void> deleteAccepted(Set<String> operationIds) async {
    for (final id in operationIds) {
      await (delete(pendingNoteOperations)
            ..where((t) => t.operationId.equals(id)))
          .go();
    }
  }

  Future<void> runInTransaction(Future<void> Function() fn) {
    return transaction(fn);
  }
```

- [ ] **Step 3: Run analyzer to confirm no errors**

```bash
cd "C:\Users\rigleyc\projects\supanotes" && flutter analyze lib/core/database/daos/note_operations_dao.dart
```
Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add lib/core/database/daos/note_operations_dao.dart
git commit -m "feat(dao): add sync session, outbox status, and rebase DAO methods"
```

---

### Task 6: Flutter — Serial queue + `sync_session` orchestration

**Ordering dependency:** implement the pure rebaser currently described in
Task 7 *before* this task. Task 6 imports it and invokes it inside the response
transaction. Task 7's adapter work remains after Task 6.

**Files:**
- Modify: `lib/core/sync/note_operations_sync_service.dart`
- Modify: `lib/features/notes/data/note_operations_api.dart`

- [ ] **Step 1: Update `SyncResult` to include `remoteOperations` and `canonicalDocument`**

In `note_operations_sync_service.dart`:

```dart
class SyncResult {
  final int acceptedCount;
  final List<String> acceptedOperationIds;
  final int finalRevision;
  final List<Operation> remoteOperations;
  final NoteDocumentResponse? canonicalDocument;

  SyncResult({
    required this.acceptedCount,
    required this.acceptedOperationIds,
    required this.finalRevision,
    required this.remoteOperations,
    this.canonicalDocument,
  });

  static SyncResult empty() => SyncResult(
    acceptedCount: 0,
    acceptedOperationIds: [],
    finalRevision: 0,
    remoteOperations: [],
  );
}
```

Construct `NoteOperationRebaser(localActorId: currentUserId)` in the sync
service. Extend `NoteOperationsSyncService` and its provider with a required
`actorId`; keep the existing `clientId` only for the HTTP request field.

Update `SyncError` imports to support `Operation` from the API.

- [ ] **Step 2: Update `SyncResponse` in `note_operations_api.dart`**

Add `canonicalDocument` field:

```dart
class SyncResponse {
  final List<AcceptedOperation> accepted;
  final int finalRevision;
  final List<Operation> remoteOperations;
  final Map<String, dynamic>? canonicalDocument;
  final DateTime serverTime;

  SyncResponse({
    required this.accepted,
    required this.finalRevision,
    required this.remoteOperations,
    this.canonicalDocument,
    required this.serverTime,
  });

  factory SyncResponse.fromJson(Map<String, dynamic> json) {
    return SyncResponse(
      accepted: (json['accepted'] as List)
          .map((e) => AcceptedOperation.fromJson(e as Map<String, dynamic>))
          .toList(),
      finalRevision: json['finalRevision'] as int,
      remoteOperations: (json['remoteOperations'] as List)
          .map((e) => Operation.fromJson(e as Map<String, dynamic>))
          .toList(),
      canonicalDocument: json['canonicalDocument'] as Map<String, dynamic>?,
      serverTime: DateTime.parse(json['serverTime'] as String),
    );
  }
}
```

Update `OperationsListResponse` to include `document` and `revision`:

```dart
class OperationsListResponse {
  final List<Operation> operations;
  final Map<String, dynamic>? document;
  final int? revision;

  OperationsListResponse({
    required this.operations,
    this.document,
    this.revision,
  });

  factory OperationsListResponse.fromJson(Map<String, dynamic> json) {
    return OperationsListResponse(
      operations: (json['operations'] as List)
          .map((e) => Operation.fromJson(e as Map<String, dynamic>))
          .toList(),
      document: json['document'] as Map<String, dynamic>?,
      revision: json['revision'] as int?,
    );
  }
}
```

- [ ] **Step 3: Add serial queue to `NoteOperationsSyncService`**

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

Add field to `NoteOperationsSyncService`:

```dart
final _syncQueue = _NoteSyncQueue();

Future<T> runSerialized<T>(String noteId, Future<T> Function() fn) {
  return _syncQueue.run(noteId, fn);
}
```

Add `required String actorId` to the service constructor and initialize:

```dart
_rebaser = NoteOperationRebaser(localActorId: actorId);
```

In `noteOperationsSyncServiceProvider`, pass
`ref.watch(currentUserIdProvider)!` as `actorId`. Do not substitute its
per-installation `clientId`.

- [ ] **Step 4: Rewrite `syncPending` with `sync_session` lifecycle**

```dart
Future<SyncResult> syncPending(String noteId) async {
  return _syncQueue.run(noteId, () async {
    final activeSession = await _dao.getSyncSession(noteId);
    if (activeSession != null) {
      return _resumeSyncSession(noteId, activeSession);
    }

    final ops = await _dao.getPendingOperations(noteId, status: 'pending');
    if (ops.isEmpty) {
      final doc = await _dao.watchNoteDocument(noteId).first;
      return SyncResult.empty();
    }

    final inFlightIds = ops.map((o) => o.operationId).toSet();
    final doc = await _dao.watchNoteDocument(noteId).first;
    final knownRevision = doc?.revision ?? 0;

    // 1. Mark in_flight + create session (transaction)
    await _dao.runInTransaction(() async {
      await _dao.markInFlight(noteId, inFlightIds);
      await _dao.upsertSyncSession(
        SyncSessionsCompanion.insert(
          noteId: noteId,
          knownRevision: knownRevision,
          operationIds: jsonEncode(inFlightIds.toList()),
          startedAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );
    });

    // 2. POST
    final request = SyncRequest(
      knownRevision: knownRevision,
      operations: ops
          .map((op) => OperationRequest(
                operationId: op.operationId,
                baseRevision: op.baseRevision,
                kind: op.kind,
                blockId: op.blockId,
                payload: parsePayload(op.payloadJson),
              ))
          .toList(),
      clientId: _clientId,
    );

    SyncResponse response;
    try {
      response = await _api.syncOperations(noteId, request);
    } catch (e) {
      // On error, keep the session for retry
      rethrow;
    }

    // 3. Process response (transaction)
    await _dao.runInTransaction(() async {
      final acceptedIds = response.accepted
          .map((a) => a.operationId)
          .toSet();
      if (!_setEquals(acceptedIds, inFlightIds)) {
        throw StateError(
          'Protocol error: server accepted ${acceptedIds.length}/'
          '${inFlightIds.length} ops. All-or-nothing required.',
        );
      }

      await _dao.deleteAccepted(inFlightIds);
      final remaining = await _dao.getPendingOperations(noteId, status: 'pending');

      final rebased = _rebaser.rebase(
        pending: remaining,
        remote: response.remoteOperations,
        finalRevision: response.finalRevision,
      );
      final canonical = response.canonicalDocument;
      if (canonical == null) {
        throw StateError('Successful sync response must include canonicalDocument');
      }
      await _dao.upsertNoteDocument(
        LocalNoteDocumentsCompanion.insert(
          noteId: noteId,
          revision: response.finalRevision,
          documentJson: encodeDocument(canonical),
          updatedAt: response.serverTime,
        ),
      );
      await _dao.replacePendingOps(noteId, rebased);

      await _dao.deleteSyncSession(noteId);
    });

    return SyncResult(
      acceptedCount: response.accepted.length,
      acceptedOperationIds: inFlightIds.toList(),
      finalRevision: response.finalRevision,
      remoteOperations: response.remoteOperations,
      canonicalDocument: NoteDocumentResponse(
        noteId: noteId,
        revision: response.finalRevision,
        document: response.canonicalDocument!,
        serverTime: response.serverTime,
      ),
    );
  });
}
```

- [ ] **Step 5: Add `_resumeSyncSession` recovery method**

```dart
Future<SyncResult> _resumeSyncSession(String noteId, SyncSessionData session) async {
  final operationIds = List<String>.from(
    jsonDecode(session.operationIds) as List,
  );

  // Load persisted in_flight rows
  final ops = await _dao.getPendingOperations(noteId, status: 'in_flight');
  final loadedIds = ops.map((o) => o.operationId).toSet();
  if (!_setEquals(loadedIds, operationIds.toSet())) {
    // Mismatch: session is corrupted, remove and fall through
    await _dao.deleteSyncSession(noteId);
    return syncPending(noteId);
  }

  // Re-send same POST
  final request = SyncRequest(
    knownRevision: session.knownRevision,
    operations: ops
        .map((op) => OperationRequest(
              operationId: op.operationId,
              baseRevision: op.baseRevision,
              kind: op.kind,
              blockId: op.blockId,
              payload: parsePayload(op.payloadJson),
            ))
        .toList(),
    clientId: _clientId,
  );

  try {
    final response = await _api.syncOperations(noteId, request);
    return _processSyncResponse(noteId, response, operationIds.toSet());
  } catch (e) {
    rethrow;
  }
}

Future<SyncResult> _processSyncResponse(
  String noteId,
  SyncResponse response,
  Set<String> expectedIds,
) async {
  await _dao.runInTransaction(() async {
      final acceptedIds = response.accepted
          .map((a) => a.operationId)
          .toSet();
      if (!_setEquals(acceptedIds, expectedIds)) {
        throw StateError(
          'Protocol error during recovery: accepted ${acceptedIds.length}'
          '/${expectedIds.length}',
        );
      }

      await _dao.deleteAccepted(expectedIds);
      final remaining = await _dao.getPendingOperations(noteId, status: 'pending');

      final canonical = response.canonicalDocument;
      if (canonical == null) {
        throw StateError('Successful sync response must include canonicalDocument');
      }
      final rebased = _rebaser.rebase(
        pending: remaining,
        remote: response.remoteOperations,
        finalRevision: response.finalRevision,
      );
      await _dao.upsertNoteDocument(
        LocalNoteDocumentsCompanion.insert(
          noteId: noteId,
          revision: response.finalRevision,
          documentJson: encodeDocument(canonical),
          updatedAt: response.serverTime,
        ),
      );
      await _dao.replacePendingOps(noteId, rebased);
      await _dao.deleteSyncSession(noteId);
    });

  return SyncResult(
    acceptedCount: response.accepted.length,
    acceptedOperationIds: expectedIds.toList(),
    finalRevision: response.finalRevision,
    remoteOperations: response.remoteOperations,
      canonicalDocument: NoteDocumentResponse(
        noteId: noteId,
        revision: response.finalRevision,
        document: response.canonicalDocument!,
        serverTime: response.serverTime,
      ),
  );
}

bool _setEquals(Set<String> a, Set<String> b) {
  if (a.length != b.length) return false;
  for (final e in a) {
    if (!b.contains(e)) return false;
  }
  return true;
}
```

- [ ] **Step 6: Rebase inside the response transaction**

`_rebaser.rebase()` is pure: it receives pending rows, remote operations and
`finalRevision`, returns transformed rows with sequential bases, and omits
no-ops. Call it inside both normal and recovery response transactions, then
persist its result with `replacePendingOps`. Do not add a separate
`updatePendingOperationBaseRevision` path and do not defer payload
transformation to the adapter.

- [ ] **Step 7: Implement `pollAndReconcile` through the same transaction**

```dart
Future<SyncResult> pollAndReconcile(String noteId) {
  return _syncQueue.run(noteId, () async {
    final session = await _dao.getSyncSession(noteId);
    if (session != null) return _resumeSyncSession(noteId, session);

    final confirmed = await _dao.watchNoteDocument(noteId).first;
    final response = await _api.getOperationsSince(
      noteId,
      confirmed?.revision ?? 0,
    );
    if (response.document == null || response.revision == null) {
      throw StateError('Polling response must include document and revision');
    }
    final pending = await _dao.getPendingOperations(noteId, status: 'pending');
    final rebased = _rebaser.rebase(
      pending: pending,
      remote: response.operations,
      finalRevision: response.revision!,
    );
    await _dao.runInTransaction(() async {
      await _dao.upsertNoteDocument(...canonical polling snapshot...);
      await _dao.replacePendingOps(noteId, rebased);
    });
    return SyncResult.fromPolling(noteId, response);
  });
}
```

- [ ] **Step 8: Add convenience methods to sync service**

```dart
Future<int> getProjectedOutboxOperationCount(String noteId) {
  return _dao.getProjectedOutboxOperationCount(noteId);
}

/// Loads the committed pending projection for adapter rebuild only.
Future<List<PendingNoteOperationData>> loadPendingProjection(String noteId) async {
  return _dao.getPendingOperations(noteId, status: 'pending');
}

/// Gets pending ops with any status (no filter).
Future<List<PendingNoteOperationData>> getPendingOperations(String noteId) {
  return _dao.getPendingOperations(noteId);
}
```

- [ ] **Step 9: Run analyzer**

```bash
cd "C:\Users\rigleyc\projects\supanotes" && flutter analyze lib/core/sync/note_operations_sync_service.dart lib/features/notes/data/note_operations_api.dart
```
Expected: No issues found.

- [ ] **Step 10: Commit**

```bash
git add lib/core/sync/ lib/features/notes/data/
git commit -m "feat(sync): serial queue, sync_session lifecycle, consistent poll"
```

---

### Task 7: Flutter — pure `NoteOperationRebaser`

**Files:**
- Create: `lib/features/notes/domain/note_operation_rebaser.dart`
- Modify: `test/features/notes/domain/note_operation_rebaser_test.dart`

The rebaser has no `MutableDocument`, `Editor`, provider, or DAO dependency.
It owns `transformTextPair`, block-operation transforms, payload serialization,
no-op elimination, and sequential `baseRevision` assignment. This makes it
safe to invoke inside the sync service's SQLite response transaction.

For every text pair, construct keys as
`'$actorId:$operationId'`: local uses `localActorId` injected into the rebaser;
remote uses `Operation.actorId`. Never use `noteId` or the per-device
`clientId` as an actor key.

- [ ] **Step 1: Write tests for `transformTextPair`**

In `test/features/notes/domain/note_operation_rebaser_test.dart`, add a new group:

```dart
import 'package:dart_quill_delta/dart_quill_delta.dart' as quill;

// ... inside main ...

group('OT transform', () {
  test('transformTextPair converges', () {
    // Both local and remote insert at position 0
    // After mirrored transform, both sides should produce same document
    final local = quill.Delta()..insert('AB');
    final remote = quill.Delta()..insert('CD');

    // Simulate client: local already applied, remote arrives
    final clientPair = transformTextPair(
      local: local,
      remote: remote,
      localKey: 'actor1:op-a',
      remoteKey: 'actor2:op-b',
    );

    // Simulate server: remote applied, local arrives
    final serverPair = transformTextPair(
      local: remote,
      remote: local,
      localKey: 'actor2:op-b',
      remoteKey: 'actor1:op-a',
    );

    // Applying local then clientPair.remote should equal remote then serverPair.local
    final clientDoc = quill.Delta()..compose(local)..compose(clientPair.remote);
    final serverDoc = quill.Delta()..compose(remote)..compose(serverPair.local);
    expect(clientDoc.toJson(), serverDoc.toJson());
  });

  test('transformTextPair handles delete + insert', () {
    final local = quill.Delta()..retain(3)..insert('llo');
    final remote = quill.Delta()..delete(3)..insert('X');
    final pair = transformTextPair(
      local: local,
      remote: remote,
      localKey: 'actor1:op-a',
      remoteKey: 'actor2:op-b',
    );
    final result = quill.Delta()..compose(local)..compose(pair.remote);
    // Should contain user's "llo" after server's "X"
    final text = extractText(result);
    expect(text, contains('llo'));
  });
});

String extractText(quill.Delta delta) {
  final buf = StringBuffer();
  for (final op in delta.toList()) {
    if (op.insert != null && op.insert is String) {
      buf.write(op.insert as String);
    }
  }
  return buf.toString();
}
```

- [ ] **Step 2: Run to confirm tests fail**

```bash
cd "C:\Users\rigleyc\projects\supanotes" && flutter test test/features/notes/domain/note_operation_rebaser_test.dart --plain-name "transformTextPair"
```
Expected: Fails with undefined `transformTextPair`.

- [ ] **Step 3: Implement `transformTextPair`**

Add to `note_operation_rebaser.dart`:

```dart
import 'package:dart_quill_delta/dart_quill_delta.dart' as quill;

class TransformPair {
  final quill.Delta local;
  final quill.Delta remote;
  TransformPair({required this.local, required this.remote});
}

TransformPair transformTextPair({
  required quill.Delta local,
  required quill.Delta remote,
  required String localKey,
  required String remoteKey,
}) {
  final localHasPriority = localKey.compareTo(remoteKey) > 0;
  final localAfterRemote = remote.transform(local, !localHasPriority);
  final remoteAfterLocal = local.transform(remote, localHasPriority);
  return TransformPair(local: localAfterRemote, remote: remoteAfterLocal);
}
```

- [ ] **Step 4: Run tests to confirm pass**

```bash
cd "C:\Users\rigleyc\projects\supanotes" && flutter test test/features/notes/domain/note_operation_rebaser_test.dart --plain-name "transformTextPair"
```
Expected: PASS

- [ ] **Step 5: Implement block transform in the pure rebaser**

Add to `note_operation_rebaser.dart`:

```dart
/// Returns a transformed payload or `null` if the operation is a no-op (should be cancelled).
Map<String, dynamic>? _transformBlockOp(
  PendingNoteOperationData pendingOp,
  List<Operation> remoteOps,
) {
  final kind = pendingOp.kind;
  final payload = parsePayload(pendingOp.payloadJson);
  final blockId = pendingOp.blockId;

  for (final remote in remoteOps) {
    final rKind = remote.kind;
    final rPayload = remote.payload;

    if (kind == 'create_block') {
      final afterBlockId = payload['afterBlockId'] as String?;
      if (rKind == 'delete_block' && afterBlockId == remote.blockId) {
        payload['afterBlockId'] = null; // prepend
      }
      if (rKind == 'create_block') {
        final rAfter = rPayload['afterBlockId'] as String?;
        if (afterBlockId != null && afterBlockId == rAfter) {
          // Tiebreak: min(operationId) comes first
          final rId = remote.blockId ?? remote.payload['id'] as String?;
          if (rId != null && pendingOp.operationId.compareTo(rId) > 0) {
            payload['afterBlockId'] = rId; // anchor shifts to first block
          }
        }
      }
    }

    if (kind == 'move_block') {
      final targetId = payload['blockId'] as String?;
      if (rKind == 'delete_block' && targetId == remote.blockId) {
        return null; // no-op: block was deleted
      }
      final afterBlockId = payload['afterBlockId'] as String?;
      if (rKind == 'delete_block' && afterBlockId == remote.blockId) {
        payload['afterBlockId'] = null; // prepend
      }
      if (rKind == 'move_block') {
        final rTarget = rPayload['blockId'] as String?;
        if (targetId == rTarget) {
          // Both moved same block. Last-write-wins by operationId.
          if (pendingOp.operationId.compareTo(remote.operationId) < 0) {
            return null; // remote move wins
          }
        }
      }
    }

    if (kind == 'delete_block') {
      if (rKind == 'delete_block' && blockId == remote.blockId) {
        return null; // no-op: already deleted
      }
    }

    if (kind == 'set_block_type') {
      if (rKind == 'delete_block' && blockId == remote.blockId) {
        return null; // no-op: block gone
      }
      if (rKind == 'set_block_type' && blockId == remote.blockId) {
        // Both set type. Surviving op wins when sent later.
        // No transform needed for the surviving op.
      }
    }
  }

  return payload;
}
```

- [ ] **Step 6: Write tests for block transform rules**

Add test cases in `note_operation_rebaser_test.dart`:

```dart
group('block transform', () {
  test('create(after:X) + delete(X) => prepend', () {
    final payload = _transformBlockOp(
      PendingNoteOperationData(...),
      [Operation(kind: 'delete_block', blockId: 'X', ...)],
    );
    expect(payload, isNotNull);
    expect(payload!['afterBlockId'], isNull);
  });

  test('move(X) + delete(X) => no-op', () {
    final payload = _transformBlockOp(
      PendingNoteOperationData(kind: 'move_block', blockId: 'X', payloadJson: '...'),
      [Operation(kind: 'delete_block', blockId: 'X', ...)],
    );
    expect(payload, isNull);
  });

  test('delete(X) + delete(X) => no-op', () {
    final payload = _transformBlockOp(
      PendingNoteOperationData(kind: 'delete_block', blockId: 'X', ...),
      [Operation(kind: 'delete_block', blockId: 'X', ...)],
    );
    expect(payload, isNull);
  });

  test('create(after:X) + create(after:X) => anchor shifts', () {
    final op1 = PendingNoteOperationData(operationId: 'bbbb', ...);
    final op2 = Operation(operationId: 'aaaa', blockId: 'new-block', payload: {'id': 'new-block', 'afterBlockId': 'X'}, ...);
    final payload = _transformBlockOp(op1, [op2]);
    expect(payload, isNotNull);
    expect(payload!['afterBlockId'], 'new-block'); // anchored after the earlier op
  });
});
```

- [ ] **Step 7: Commit**

```bash
git add lib/features/notes/domain/note_operation_rebaser.dart test/features/notes/domain/note_operation_rebaser_test.dart
git commit -m "feat(sync): add pure operation rebaser"
```

---

### Task 8: Flutter — rebuild the editor projection

- [ ] **Step 1: Write test for `rebuildFromSnapshot`**

```dart
group('reconcile', () {
  test('rebuildFromSnapshot produces correct document state', () async {
    final adapter = createAdapter();
    adapter.start();
    await Future.delayed(Duration.zero);

    final snapshot = {
      'blocks': [
        {'id': 'block-1', 'type': 'paragraph', 'delta': [{'insert': 'Server text'}]},
        {'id': 'block-2', 'type': 'paragraph', 'delta': [{'insert': 'Another'}]},
      ],
    };

    await adapter.rebuildFromSnapshot(snapshot: snapshot, rebasedOps: null);

    final node1 = document.getNodeById('block-1');
    expect(node1, isNotNull);
    if (node1 is TextNode) {
      expect(node1.text.toPlainText(), 'Server text');
    }
    expect(document.nodeCount, 2);
  });
});
```

- [ ] **Step 2: Implement `reconcile()` + `rebuildFromSnapshot()`**

Add to adapter:

```dart
/// The service has already atomically persisted canonical snapshot and rebased
/// outbox. The adapter only rebuilds the in-memory projection.
Future<void> reconcile(SyncResult result) async {
  final canonical = result.canonicalDocument;
  if (canonical == null) return;
  final rebasedOps = await _syncService.loadPendingProjection(_noteId);
  await rebuildFromSnapshot(
    snapshot: canonical.document,
    rebasedOps: rebasedOps,
  );
}

/// Rebuild the visible MutableDocument from canonical snapshot + rebased outbox.
Future<void> rebuildFromSnapshot({
  required Map<String, dynamic> snapshot,
  required List<PendingNoteOperationData>? rebasedOps,
}) async {
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

Add IME composition tracking:

```dart
bool _isComposing = false;

void onCompositionStart() => _isComposing = true;
void onCompositionEnd() {
  _isComposing = false;
  if (_pendingRebuild != null) {
    final req = _pendingRebuild!;
    _pendingRebuild = null;
    unawaited(rebuildFromSnapshot(snapshot: req.snapshot, rebasedOps: req.ops));
  }
}
```

- [ ] **Step 3: Add `_applyOperationRequest` for `OperationRequest` (in addition to `Operation`)**

```dart
void _applyOperationRequest(PendingNoteOperationData op) {
  _applyOperation(Operation(
    operationId: op.operationId,
    noteId: op.noteId,
    revision: op.baseRevision,
    baseRevision: op.baseRevision,
    kind: op.kind,
    blockId: op.blockId,
    payload: parsePayload(op.payloadJson),
    createdAt: op.createdAt,
  ));
}
```

- [ ] **Step 4: Update `_flushLocalOps` to use `projectedOutboxCount`**

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

- [ ] **Step 5: Use the projection loader from Task 6**

`reconcile()` calls `NoteOperationsSyncService.loadPendingProjection()`. Do not
duplicate DAO reads or transformation code in the adapter.

The full flow is:
1. Sync service: POST/poll → pure rebase → replace pending outbox + save snapshot + delete session, in one transaction.
2. Adapter.reconcile(): load the committed projection → rebuild `MutableDocument` only.

- [ ] **Step 6: Run all adapter tests**

```bash
cd "C:\Users\rigleyc\projects\supanotes" && flutter test test/features/notes/domain/note_operation_adapter_test.dart
```
Expected: All passing.

- [ ] **Step 7: Commit**

```bash
git add lib/features/notes/domain/ lib/core/sync/
git commit -m "feat(adapter): reconcile + rebuildFromSnapshot"
```

---

### Task 9: Flutter — Wire provider with serial queue

**Files:**
- Modify: `lib/features/notes/presentation/controllers/note_editor_provider.dart`

- [ ] **Step 1: Rewrite provider to use serial queue + call `reconcile`**

```dart
import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/notes/data/note_operations_api.dart';
import 'package:supanotes/features/notes/domain/note_operation_adapter.dart';
import 'note_editor_controller.dart';

final noteEditorControllerProvider = Provider.autoDispose
    .family<NoteEditorController, String>((ref, noteId) {
  final userId = ref.watch(currentUserIdProvider)!;
  final attachmentsRepo = ref.read(attachmentsRepositoryProvider);
  final controller = NoteEditorController(
    userId: userId,
    onUploadFile: (id, filePath, mimeType) => attachmentsRepo.upload(
      id: id,
      noteId: noteId,
      file: File(filePath),
      mimeType: mimeType,
    ),
  );

  controller.initOtOnly(noteId: noteId);

  var disposed = false;

  final noteOpsSyncService = ref.read(noteOperationsSyncServiceProvider);
  final adapter = NoteOperationAdapter(
    document: controller.document!,
    syncService: noteOpsSyncService,
    noteId: noteId,
    editor: controller.editor!,
  );

  adapter.onLocalOperations = (_) {
    // syncPending owns the per-note queue. Do not wrap it in runSerialized,
    // otherwise it queues itself behind the currently executing task.
    unawaited(noteOpsSyncService.syncPending(noteId).then((result) async {
      if (!disposed && result.canonicalDocument != null) {
        await adapter.reconcile(result);
      }
    }).catchError((error, stackTrace) {
      // Log/report the failure; do not silently discard a failed sync.
      dev.log('Note operation sync failed', error: error, stackTrace: stackTrace);
    }));
  };

  unawaited(adapter.start().then((_) {
    if (disposed) return;
    controller.operationAdapter = adapter;
  }));

  Timer? pollTimer;
  void startPolling() {
    pollTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (disposed) return;
      try {
        // pollAndReconcile owns the same queue, first recovers any orphan
        // sync_session, then atomically rebases/persists the polling response.
        final result = await noteOpsSyncService.pollAndReconcile(noteId);
        if (!disposed && result.canonicalDocument != null) {
          await adapter.reconcile(result);
        }
      } catch (error, stackTrace) {
        dev.log('Note operation poll failed', error: error, stackTrace: stackTrace);
      }
    });
  }
  startPolling();

  ref.onDispose(() {
    disposed = true;
    pollTimer?.cancel();
    unawaited(controller.dispose());
  });
  return controller;
});
```

- [ ] **Step 2: Run analyzer**

```bash
cd "C:\Users\rigleyc\projects\supanotes" && flutter analyze lib/features/notes/presentation/controllers/
```
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add lib/features/notes/presentation/controllers/
git commit -m "feat(provider): serial queue + reconcile wiring"
```

---

### Task 10: Integration tests

**Files:**
- Modify: `test/features/notes/domain/note_operation_adapter_test.dart`
- Create: `test/features/notes/domain/sync_reconciliation_test.dart`

Write each test following TDD. Example for the first test:

- [ ] **Step 1: Write test — two offline inserts get sequential baseRevisions**

In a new file `test/features/notes/domain/sync_reconciliation_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/notes/domain/note_operation_adapter.dart';

class MockSyncService extends Mock implements NoteOperationsSyncService {}

void main() {
  late MockSyncService mockSyncService;
  late MutableDocument document;
  late MutableDocumentComposer composer;
  late Editor editor;

  setUp(() {
    mockSyncService = MockSyncService();
    document = MutableDocument(nodes: [
      ParagraphNode(id: 'block-1', text: AttributedText('Hello')),
    ]);
    composer = MutableDocumentComposer();
    editor = createDefaultDocumentEditor(document: document, composer: composer);
  });

  NoteOperationAdapter createAdapter() {
    return NoteOperationAdapter(
      document: document,
      syncService: mockSyncService,
      noteId: 'note-1',
      editor: editor,
    );
  }

  group('baseRevision', () {
    test('two offline inserts in same block get sequential baseRevisions', () async {
      when(() => mockSyncService.generateOperationId()).thenReturn('op-1');
      when(() => mockSyncService.getProjectedOutboxOperationCount('note-1'))
          .thenAnswer((_) async => 0);
      when(() => mockSyncService.enqueueOperation(any(), any()))
          .thenAnswer((_) async {});
      when(() => mockSyncService.getPendingOperations('note-1'))
          .thenAnswer((_) async => []);
      when(() => mockSyncService.getConfirmedDocument('note-1'))
          .thenAnswer((_) async => null);

      final adapter = createAdapter();
      adapter.onLocalOperations = (_) {};
      adapter.start();
      await Future.delayed(Duration.zero);

      // First insert at end of "Hello"
      editor.execute([
        InsertTextRequest(
          documentPosition: DocumentPosition(
            nodeId: 'block-1',
            nodePosition: const TextNodePosition(offset: 5),
          ),
          textToInsert: ' first',
          attributions: {},
        ),
      ]);
      await adapter.flushNow();

      when(() => mockSyncService.getProjectedOutboxOperationCount('note-1'))
          .thenAnswer((_) async => 1);
      when(() => mockSyncService.generateOperationId()).thenReturn('op-2');

      // Second insert at end of "Hello first"
      editor.execute([
        InsertTextRequest(
          documentPosition: DocumentPosition(
            nodeId: 'block-1',
            nodePosition: const TextNodePosition(offset: 11),
          ),
          textToInsert: ' second',
          attributions: {},
        ),
      ]);
      await adapter.flushNow();

      final ops = await mockSyncService.getPendingOperations('note-1');
      // Both captured ops verify baseRevisions
      final captured = verify(() => mockSyncService.enqueueOperation(any(), captureAny()))
          .captured.cast<OperationRequest>();
      expect(captured.length, 2);
      expect(captured[0].baseRevision + 1, captured[1].baseRevision);
    });
  });

  group('block transform', () {
    test('create after deleted block falls back to prepend', () {
      // ...concrete test...
    });
    test('create after the same anchor shifts anchor', () {
      // ...concrete test...
    });
  });

  group('rebuild', () {
    test('rebuildFromSnapshot replaces editor content', () async {
      // ...concrete test...
    });
  });
}
```

- [ ] **Step 2: Run to confirm test fails**

```bash
cd "C:\Users\rigleyc\projects\supanotes" && flutter test test/features/notes/domain/sync_reconciliation_test.dart
```
Expected: Fails on missing mocks or import errors.

- [ ] **Step 3: Complete all integration tests**

Write remaining tests — each test follows the same TDD pattern:

- `concurrent sync + edit during request`: mock sync service, simulate a pending POST while a new edit comes in, verify the new op gets `baseRevision = confirmedRevision + projectedCount`
- `polling with pending outbox`: simulate poll returning remote ops and verify the service commits rebased outbox before adapter rebuild
- `create(after:X) from two devices`: call `NoteOperationRebaser` with both ops, verify anchor shifts to min(opId)
- `app restart with orphan sync_session`: set up sync_session in mock DAO, verify recovery flow re-sends POST
- `IME composition + rebuild`: set _isComposing=true, call rebuildFromSnapshot, verify it defers

- [ ] **Step 4: Run full test suite**

```bash
cd "C:\Users\rigleyc\projects\supanotes" && flutter test
```
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add test/
git commit -m "test: sync reconciliation integration tests"
```

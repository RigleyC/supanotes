# Plan 048: Flush NodeSyncManager Before Disposing the Editor

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat bfebe7e..HEAD -- lib/features/notes/domain/node_sync_manager.dart lib/features/notes/presentation/controllers/note_editor_controller.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: plans/046-editor-round-trip-characterization-tests.md
- **Category**: bug
- **Planned at**: commit `bfebe7e`, 2026-07-06

## Why this matters

When the user closes a note, `NoteEditorController.dispose()` fires
synchronously. It calls `_nodeSyncManager?.dispose()`, which calls
`_drainQueue()` — but doesn't `await` it. The next line (`document?.dispose()`)
tears down the `MutableDocument` underneath an in-flight async DB transaction
that's still reading content from it. The `_writeLock`'s `try/catch` (line
71-73) silently swallows the resulting `StateError` / `CastError` via `print`,
and the user loses the last 500ms of their typing — usually the word that made
them close the note. Worst-case silent data loss in a notes app.

## Current state

### Files in scope

- `lib/features/notes/domain/node_sync_manager.dart` — owns the debounce
  timer, the write-lock chain, and `_drainQueue`. Currently exposes a
  fire-and-forget `dispose()`.
- `lib/features/notes/presentation/controllers/note_editor_controller.dart` —
  calls `_nodeSyncManager?.dispose()` then immediately destroys document,
  editor, composer, focusNode.

### Current code

`node_sync_manager.dart` — `dispose` (lines 707-711):

```dart
void dispose() {
  _debounceTimer?.cancel();
  _drainQueue();                 // ← fire-and-forget
  _document.removeListener(_onDocumentChanged);
}
```

`_drainQueue` (lines 180-279) is `Future<void>` and reads `_document` inside
`_db.transaction`. The `_buildContentSnapshot` call on line 187 iterates
`_document.where((n) => ...)`, which throws `ConcurrentModificationError` or
`StateError: Document has been disposed` if the document is torn down while the
scheduled microtask runs.

`_writeLock` catch (lines 67-75):

```dart
void _enqueueDbWrite(FutureOr<void> Function() action) {
  _writeLock = _writeLock.then((_) async {
    try {
      await action();
    } catch (e, stackTrace) {
      print('[NodeSyncManager] SQLite Write Error: $e\n$stackTrace');  // swallowed
    }
  });
}
```

But `_drainQueue()` is called directly in `dispose`, not via `_enqueueDbWrite` —
so an exception there propagates uncaught (or, if scheduled into a microtask,
becomes an orphaned future). Either way, the flush races `_document` disposal.

`note_editor_controller.dart` — `dispose` (lines 242-249):

```dart
void dispose() {
  _flushAndSaveFinalState();
  _nodeSyncManager?.dispose();      // ← doesn't await
  editor?.dispose();
  document?.dispose();              // ← tears down doc while flush reads it
  composer?.dispose();
  focusNode.dispose();
}
```

### Repository conventions

- `dispose()` methods in Flutter are synchronous by contract. We cannot make
  `dispose()` return `Future<void>` without breaking the `Provider.onDispose`
  wiring in `note_editor_provider.dart:14`. So the fix must keep
  `dispose()` synchronous but ensure the flush completes BEFORE the document
  is disposed. That means: snapshot synchronously, complete write in
  background, then disposal of document is safe.
- AGENTS.md error rule: "Errors não podem ser engolidos" — currently the
  `print` in `_enqueueDbWrite` violates this. Leave that for whichever future
  plan handles it; this fix only addresses the dispose race.
- Do not add code comments unless asked by the plan.

## Commands you will need

| Purpose          | Command                                                                            | Expected on success |
|------------------|------------------------------------------------------------------------------------|---------------------|
| Run test         | `flutter test test/features/notes/presentation/controllers/note_editor_controller_test.dart --plain-name "048"` | all pass after flip |
| Run full editor tests | `flutter test test/features/notes/`                                            | all pass            |
| Static analysis  | `dart analyze lib/features/notes/domain/node_sync_manager.dart lib/features/notes/presentation/controllers/note_editor_controller.dart` | no errors |

## Scope

**In scope** (the only files you should modify):
- `lib/features/notes/domain/node_sync_manager.dart`
- `lib/features/notes/presentation/controllers/note_editor_controller.dart`
- `test/features/notes/presentation/controllers/note_editor_controller_test.dart` — flip `BUG 048` assertion only

**Out of scope** (do NOT touch):
- `note_editor_provider.dart` — `ref.onDispose` contract is sync; do not
  change.
- `_writeLock` error handling (line 71-73) — that's a separate finding
  (plan 050). Leave the `print` alone.
- The `ProviderScope` / Riverpod disposal timing.

## Git workflow

- Branch: `fix/048-sync-manager-flush-before-dispose`
- Commit: `fix(editor): flush NodeSyncManager synchronously before document disposal`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Flip the characterization test

Open `test/features/notes/presentation/controllers/note_editor_controller_test.dart`,
find the test prefixed `BUG 048`. The current assertion is approximately:

```dart
expect(rows.any((r) => r.id == 'p1'), isFalse,
    reason: 'BUG 048: dispose does not await final flush — last 500ms of edits lost');
```

Change to assert the FIXED behavior:

```dart
expect(rows.any((r) => r.id == 'p1'), isTrue,
    reason: 'Plan 048: flush completes synchronously before document disposal');
final row = rows.firstWhere((r) => r.id == 'p1');
final data = jsonDecode(row.data) as Map<String, dynamic>;
expect(data['text'], 'last words',
    reason: 'Plan 048: flushed content matches the disposed document state');
```

The test may need adjusting in setup: after `controller.dispose()`, the test
waits for the in-memory DB to be queryable. The `_drainQueue` writes
synchronously into the in-memory SQLite handle (drift in-memory is fast); a
short `await Future.delayed(...)` after dispose is acceptable to let the
scheduled microtask complete. The test in plan 046 already has the delay or
should — if not, add `await Future.delayed(const Duration(milliseconds: 50));`
between `dispose()` and the DB query.

**Verify**: `flutter test test/features/notes/presentation/controllers/note_editor_controller_test.dart --plain-name "048"`
→ test FAILS (fix not in yet). This is the regression guard.

### Step 2: Snapshot synchronously, defer only the DB write

Open `lib/features/notes/domain/node_sync_manager.dart`. Add a new method:

```dart
/// Synchronously captures all pending ops and document content, then
/// schedules the DB write. Safe to call immediately before the document
/// is disposed — the snapshot is taken before the write lock chain reads
/// the document.
void flushNow() {
  _debounceTimer?.cancel();
  if (_pendingOps.isEmpty) return;
  final opsToProcess = List<NodeOperation>.from(_pendingOps);
  _pendingOps.clear();
  final now = DateTime.now().toUtc();
  final snapshotText = _buildContentSnapshot();

  _enqueueDbWrite(() async {
    await _applyOpsTransaction(opsToProcess, now, snapshotText);
    final flushedIds = opsToProcess.map(_opNodeId).whereType<String>().toSet();
    final stillPendingIds = _pendingOps.map(_opNodeId).whereType<String>().toSet();
    locallyDirtyNodeIds.removeAll(flushedIds.difference(stillPendingIds));
  });
}
```

### Step 3: Extract the transaction body

The body of `_drainQueue` (lines 180 to ~279) does:
1. Snapshot ops + text (lines 180-187)
2. `_db.transaction(...) { switch (op) { ... } }` (lines 189-272)
3. Clear dirty flags (lines 274-278)

Step 1 (snapshot) and step 3 (dirty-flag clear) must stay in their caller,
but the `_db.transaction` body (step 2) is identical between `_drainQueue` and
the new `flushNow`. Extract it into a private method:

```dart
Future<void> _applyOpsTransaction(
  List<NodeOperation> opsToProcess,
  DateTime now,
  String snapshotText,
) async {
  await _db.transaction(() async {
    for (final op in opsToProcess) {
      switch (op) {
        // ... existing switch body unchanged ...
      }
    }
    await _flushNoteExcerptFromSnapshot(snapshotText, now);
  });
}
```

Move the entire `switch (op) { ... }` block and the
`_flushNoteExcerptFromSnapshot(snapshotText, now);` call into this new method,
verbatim. Leave the snapshot capture (lines 183-187) and the dirty-flag cleanup
(lines 274-278) in `_drainQueue`, with a call to `_applyOpsTransaction`
replacing the inline transaction block:

```dart
Future<void> _drainQueue() async {
  if (_pendingOps.isEmpty) return;
  final opsToProcess = List<NodeOperation>.from(_pendingOps);
  _pendingOps.clear();
  final now = DateTime.now().toUtc();
  final snapshotText = _buildContentSnapshot();

  await _applyOpsTransaction(opsToProcess, now, snapshotText);

  final flushedIds = opsToProcess.map(_opNodeId).whereType<String>().toSet();
  final stillPendingIds = _pendingOps.map(_opNodeId).whereType<String>().toSet();
  locallyDirtyNodeIds.removeAll(flushedIds.difference(stillPendingIds));
}
```

### Step 4: Update `dispose()` to flush synchronously

Replace lines 707-711 with:

```dart
void dispose() {
  flushNow();
  _debounceTimer?.cancel();
  _document.removeListener(_onDocumentChanged);
}
```

`flushNow()` snapshots the document state synchronously and schedules the DB
write via `_enqueueDbWrite`. By the time `dispose()` returns, `_document` is
no longer being read by the snapshot logic; subsequent `_document.removeListener`
and the caller's `document?.dispose()` are now safe.

### Step 5: Have controller await the flush

`NoteEditorController.dispose()` (lines 242-249) must call `flushNow` (which
is synchronous) and ensure no new ops can arrive before disposal. It's already
synchronous, so no `async` change needed:

```dart
void dispose() {
  _flushAndSaveFinalState();
  _nodeSyncManager?.dispose();      // calls flushNow internally
  editor?.dispose();
  document?.dispose();
  composer?.dispose();
  focusNode.dispose();
}
```

NO change needed in `note_editor_controller.dart` IF `_nodeSyncManager?.dispose()`
is the only thing you need. But the race is that `_drainQueue` reads
`_document` AFTER `document?.dispose()`. After Step 4, `_drainQueue` is no
longer called from `dispose()`; `flushNow()` is, and it snapshots
synchronously. Verify this works:

**Verify**: `flutter test test/features/notes/presentation/controllers/note_editor_controller_test.dart --plain-name "048"`
→ test PASSES.

**Verify**: `flutter test test/features/notes/`
→ all pass.

**Verify**: `dart analyze lib/features/notes/domain/node_sync_manager.dart lib/features/notes/presentation/controllers/note_editor_controller.dart`
→ no errors.

## Test plan

The 046 plan wrote the characterization test. This plan flips its assertion.
No new tests needed.

- `flutter test test/features/notes/presentation/controllers/note_editor_controller_test.dart` → all pass

## Done criteria

- [ ] `flutter test test/features/notes/` exits 0
- [ ] `dart analyze lib/features/notes/domain/node_sync_manager.dart` exits 0
- [ ] `git diff --name-only` shows `node_sync_manager.dart` and the test file only (controller file change should be unnecessary; if you needed to touch it, justify in the commit message)
- [ ] New `flushNow()` method exists, `_drainQueue` delegates the transaction to `_applyOpsTransaction`, `dispose()` calls `flushNow()`
- [ ] The flipped `048` test passes
- [ ] `plans/README.md` status row for 048 updated to DONE

## STOP conditions

Stop and report back (do not improvise) if:

- `_drainQueue`'s structure differs from the excerpts above (e.g., the dirty-
  flag cleanup has been refactored already).
- `_db.transaction` cannot be cleanly extracted — report what blocked it and
  propose inlining the transaction body into `flushNow` (with a code
  duplication trade-off) as an alternative.
- Extracting `_applyOpsTransaction` causes a `_pendingOps` read-during-write
  warn — the `List<NodeOperation>.from(_pendingOps)` copy on line 183 is the
  key snapshot; if it's missing, STOP.
- The `048` test still fails AFTER the fix — investigate whether the test's
  `await Future.delayed(const Duration(milliseconds: 50))` is enough for the
  in-memory SQLite write to land; if not, extend to 200ms and report why.
- `_nodeSyncManager?.locallyDirtyNodeIds.removeAll(...)` in `flushNow` would
  introduce a name clash with the extracted private method — STOP and report.

## Maintenance notes

- The contract of `flushNow()`: snapshot is synchronous, DB write is
  fire-and-forget but reads only the snapshot. Any future op type that needs
  to read live `_document` state during the transaction must NOT be added to
  the queue and dumped via `flushNow` — it must be persisted synchronously by
  the operation caller, or stored as a snapshot in the `NodeOperation`.
- A reviewer should scrutinize: did the snapshot capture happen BEFORE the
  microtask started reading it? Open the `flushNow` body — line `final
  snapshotText = _buildContentSnapshot();` MUST execute outside the
  `_enqueueDbWrite` callback. If it's inside, the snapshot itself races
  disposal.
- Adding a new `NodeOperation` subclass requires updating both
  `_applyOpsTransaction` (new case) and `_opNodeId`.
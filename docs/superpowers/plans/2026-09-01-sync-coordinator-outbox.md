# Sync Coordinator + Global Outbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make note-operation sync independent from an open editor session while preserving fast local durability and reducing unnecessary network traffic.

**Architecture:** Keep `NoteOperationsSyncService` as the per-note serialized REST/OT authority. Add an app-scoped `NoteOutboxWorker` that drains inactive notes, and debounce network sends inside `NoteSyncSession` while leaving the adapter's 50 ms SQLite persistence unchanged.

**Tech Stack:** Flutter/Dart, Riverpod, Drift/SQLite, connectivity_plus, existing REST/OT sync service.

**Spec:** `docs/superpowers/specs/2026-09-01-sync-coordinator-outbox-design.md`

## Global Constraints

- Do not change REST/OT wire operation formats.
- Do not sync active notes from the global worker.
- Closing an editor session must wait for local SQLite durability only, never network success.
- Preserve orphan `sync_session` recovery through existing `syncPending()` semantics.
- Keep local operation persistence debounce at 50 ms.
- Use 350 ms as the open-session network coalescing window.

---

### Task 1: Discover pending note IDs in the DAO

**Files:**
- Modify: `lib/core/database/daos/note_operations_dao.dart`
- Test: `test/core/database/daos/note_operations_dao_test.dart`

**Interfaces:**
- Produces: `Future<List<String>> getPendingNoteIds({required String ownerUserId})`

- [ ] **Step 1: Write failing DAO tests**

Add tests proving the query returns distinct note IDs containing either `pending` or `in_flight` rows, ignores rows from another `ownerUserId`, and returns stable deterministic ordering.

- [ ] **Step 2: Run the DAO test**

Run: `flutter test test/core/database/daos/note_operations_dao_test.dart`
Expected: FAIL because `getPendingNoteIds` does not exist.

- [ ] **Step 3: Implement the query**

Use Drift over `pendingNoteOperations`, filter `ownerUserId`, restrict status to `pending`/`in_flight`, select note IDs, deduplicate, sort, and return.

- [ ] **Step 4: Re-run the DAO test**

Expected: PASS.

- [ ] **Step 5: Commit**

Commit: `feat(sync): expose pending note ids`

---

### Task 2: Add `NoteOutboxWorker`

**Files:**
- Create: `lib/core/sync/note_outbox_worker.dart`
- Test: `test/core/sync/note_outbox_worker_test.dart`

**Interfaces:**
- Consumes: `NoteOperationsDao`, `NoteOperationsSyncService`, `NoteSessionActivityTracker`, authenticated `actorId`.
- Produces: `Future<void> drain()`, `void wake()`, `Future<void> dispose()`.

- [ ] **Step 1: Write failing worker tests**

Cover:
- inactive pending note calls `syncPending`;
- active note is skipped;
- one transient failure does not prevent a second note from syncing;
- repeated wake while a drain is running coalesces instead of overlapping;
- a successful retry clears per-note backoff.

Use fakes for the sync delegate and activity tracker so tests do not require HTTP.

- [ ] **Step 2: Run worker tests**

Run: `flutter test test/core/sync/note_outbox_worker_test.dart`
Expected: FAIL because worker does not exist.

- [ ] **Step 3: Implement worker orchestration**

Use one drain tail/guard to prevent overlapping global passes. For each note ID, skip active notes, skip notes whose `nextAttemptAt` is still in the future, call the sync delegate, clear retry state on success, and record the next retry time on transient failures. Protocol errors should be suppressed until an explicit wake/restart, without deleting the outbox.

Backoff sequence: `1s, 2s, 5s, 10s, 30s, 60s`, capped at 60 s, with injectable clock/jitter for deterministic tests.

- [ ] **Step 4: Re-run worker tests**

Expected: PASS.

- [ ] **Step 5: Commit**

Commit: `feat(sync): add global note outbox worker`

---

### Task 3: Wire the worker into app lifecycle and connectivity

**Files:**
- Modify: `lib/core/di/providers.dart`
- Modify: `lib/main.dart`
- Test: `test/core/di/note_outbox_worker_provider_test.dart`

**Interfaces:**
- Produces: `noteOutboxWorkerProvider` and an app-lifetime listener/provider that keeps the worker alive while authenticated.

- [ ] **Step 1: Write provider lifecycle tests**

Verify unauthenticated state does not construct the worker; authenticated state constructs it with the current actor; provider disposal cancels connectivity/timer resources.

- [ ] **Step 2: Run provider test**

Run: `flutter test test/core/di/note_outbox_worker_provider_test.dart`
Expected: FAIL because provider does not exist.

- [ ] **Step 3: Implement Riverpod wiring**

Construct the worker from the existing sync service, DAO and activity tracker. Subscribe to `Connectivity().onConnectivityChanged`; call `wake()` when at least one connectivity result is not `ConnectivityResult.none`. Add a low-frequency safety wake while authenticated.

- [ ] **Step 4: Wire foreground wake**

In `SupaNotesApp.didChangeAppLifecycleState`, call `ref.read(noteOutboxWorkerProvider).wake()` on `resumed` when authenticated. Keep the worker alive from `build()` using a Riverpod listener/watch similarly to catalog sync.

- [ ] **Step 5: Re-run provider tests**

Expected: PASS.

- [ ] **Step 6: Commit**

Commit: `feat(sync): keep outbox draining outside editor`

---

### Task 4: Coalesce open-editor network sync

**Files:**
- Modify: `lib/features/notes/editor/sync/note_sync_session.dart`
- Test: `test/features/notes/editor/sync/note_sync_session_test.dart`

**Interfaces:**
- `NoteOperationAdapter` keeps the existing 50 ms local flush.
- `NoteSyncSession` adds a 350 ms network debounce only around `_syncPending()` scheduling.

- [ ] **Step 1: Write failing timing tests**

Using fake async or injected duration, prove multiple `onLocalOperations` notifications inside the coalescing window result in one sync call, and `flushNow()` still flushes local operations without waiting for network success.

- [ ] **Step 2: Run session tests**

Run: `flutter test test/features/notes/editor/sync/note_sync_session_test.dart`
Expected: FAIL under current immediate `_onLocalOps()` behavior.

- [ ] **Step 3: Implement network debounce**

Replace immediate `_onLocalOps()` scheduling from `_handleLocalOperations` with a resettable 350 ms timer. Keep startup and `pollNow()` semantics explicit; `flushNow()` must cancel the timer, flush adapter state, and schedule/perform sync without changing close durability semantics. Cancel the timer on dispose.

- [ ] **Step 4: Re-run session tests**

Expected: PASS.

- [ ] **Step 5: Commit**

Commit: `perf(sync): coalesce editor network flushes`

---

### Task 5: Regression for close-offline-then-global-retry

**Files:**
- Modify: `test/features/notes/editor/offline_persistence_e2e_test.dart`

**Interfaces:**
- Uses real Drift test database, real `NoteOperationsSyncService` with fake client, and `NoteOutboxWorker`.

- [ ] **Step 1: Add failing regression scenario**

Scenario:
1. edit a note;
2. force local adapter flush while remote client is offline;
3. dispose editor session;
4. assert pending operation remains in SQLite;
5. switch fake remote client online;
6. call worker `drain()`;
7. assert pending operations are empty and confirmed revision advances.

- [ ] **Step 2: Run the regression**

Run: `flutter test test/features/notes/editor/offline_persistence_e2e_test.dart`
Expected: PASS only when Tasks 1-4 are correctly integrated.

- [ ] **Step 3: Commit**

Commit: `test(sync): cover closed-note outbox recovery`

---

### Task 6: Verification

**Files:** none.

- [ ] **Step 1: Run focused sync suite**

Run: `flutter test test/core/sync test/features/notes/editor/sync test/features/notes/editor/offline_persistence_e2e_test.dart test/core/database/daos/note_operations_dao_test.dart`
Expected: PASS.

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze --no-fatal-infos`
Expected: no errors introduced by this branch.

- [ ] **Step 3: Run full Flutter test suite**

Run: `flutter test`
Expected: PASS, or document only pre-existing/environmental failures with exact evidence.

- [ ] **Step 4: Open PR against `master`**

PR should explain the closed-note outbox bug, local-vs-network durability semantics, network coalescing and backoff, and explicitly state that remote inbox/change-feed is the next independent subproject.

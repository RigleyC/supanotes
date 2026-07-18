# Sync, Yjs, Tasks and Notifications Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the YDoc the single write model for note content and task metadata, reduce sync/projection work to actual changes, and make local notifications a deterministic projection of the authenticated user's open tasks.

**Architecture:** `MutableDocument` remains the editing surface, while the YDoc becomes the only persistent command target for note nodes and task state. SQLite and PostgreSQL remain query projections; they must never be used by UI commands to independently mutate a task represented in the YDoc. Sync uses one authenticated per-note state-vector exchange for both open and background notes, while projections and notifications are coalesced after a committed YDoc change.

**Tech Stack:** Flutter/Dart, `super_editor`, `yjs_dart`, Drift/SQLite, Riverpod 3, Go, `reearth/ygo`, PostgreSQL, `flutter_local_notifications`.

## Global Constraints

- Preserve the local `packages/yjs_dart` override; do not replace it with the pub.dev version.
- Keep `YDoc` as the source of truth for `dueDate`, `hasTime`, `recurrence`, `reminder`, completion and completion timestamps.
- Use manual Riverpod providers only; no generator or `StateNotifier`.
- Keep SQL tables as projections/query indexes only; UI task actions must not call legacy direct-SQL mutation methods.
- Do not delete legacy Yjs formats until the migration gate proves every locally stored and server document has been upgraded.
- Use `AppButton`, `AppBottomSheet`, and existing shared widgets for any UI touched by the work.
- Do not log note text, titles, full Yjs payloads, state vectors, or notification bodies in production logs.

---

## Target data ownership

| Concern | Canonical write model | Derived read model |
|---|---|---|
| Node order, node type and rich text | YDoc | `notes.content`, editor document |
| Task title, completion, due date/time, recurrence, reminder | YDoc | SQLite/PostgreSQL `tasks` |
| Completion history | YDoc `lastCompletedAt` transition | task-completions tables |
| Notification schedule | SQLite `tasks` projection, scoped by user | platform pending notifications |
| Server document persistence | compact Yjs state plus pending updates | PostgreSQL projections |

## Migration gates

1. **Compatibility read:** continue accepting JSON-string node entries, `data.text`, `content/<id>`, and `content_fixed/<id>`.
2. **Canonical write:** new writes use a nested node `YMap` plus `content/<id>` `YText`; task metadata is stored inside the node map, never as `nodes["<task>:field"]` composite keys.
3. **Rewrite on touch:** when a document is locally edited, normalize only the touched node into the canonical shape.
4. **Fleet gate:** expose a server query/metric for documents still containing legacy entries or `content_fixed/` roots. Do not remove fallback readers until it reports zero for a full retention window.
5. **Removal:** delete legacy readers, composite-key compatibility, and direct-SQL UI mutations in a separately reviewable cleanup commit.

### Task 1: Characterize the current behavior and install regression gates

**Files:**
- Create: `test/features/notes/domain/yjs_task_command_test.dart`
- Create: `test/core/sync/sync_service_note_exchange_test.dart`
- Create: `test/features/tasks/domain/task_notification_reconciliation_test.dart`
- Modify: `test/sync/editor_bridge_test.dart`
- Modify: `test/core/sync/yjs_sync_manager_test.dart`
- Modify: `backend/internal/sync/protocol_test.go`
- Modify: `backend/internal/sync/convergence_test.go`

**Interfaces:**
- Produces characterization coverage used by all later tasks.
- Defines the expected task command result: `({DateTime? nextDue, DateTime previousDue, bool previousHasTime})`.

- [ ] **Step 1: Add the duplicate recurring-command regression test**

```dart
test('recurring completion produces one Yjs transaction and one projection request', () async {
  final recorder = RecordingProjectionScheduler();
  final bridge = buildBridge(projectionScheduler: recorder);

  final result = bridge.completeTaskInYDoc('task-1', now: DateTime(2026, 7, 18, 9));

  expect(result.nextDue, DateTime(2026, 7, 19, 9));
  expect(recorder.requestedNoteIds, ['note-1']);
  expect(readTaskField(bridge.doc, 'task-1', 'lastCompletedAt'), isNotNull);
});
```

- [ ] **Step 2: Run the new regression before implementation**

Run: `flutter test test/features/notes/domain/yjs_task_command_test.dart`

Expected: FAIL because `completeTaskInYDoc` and the recording projection boundary do not exist.

- [ ] **Step 3: Add sync exchange tests with a fake binary endpoint**

```dart
test('a second idle sync sends no Yjs update', () async {
  final transport = RecordingNoteSyncTransport();
  final service = buildSyncService(transport: transport);

  await service.syncDirtyNote('note-1');
  await service.syncDirtyNote('note-1');

  expect(transport.requests, hasLength(1));
});
```

- [ ] **Step 4: Add notification identity and account-isolation tests**

```dart
test('switching user cancels the previous user schedule before scheduling the next', () async {
  await scheduler.reconcile(userId: 'user-a', tasks: [task('a')]);
  await scheduler.reconcile(userId: 'user-b', tasks: [task('b')]);

  expect(plugin.cancelled, contains(notificationIdForTask('a')));
  expect(plugin.scheduledIds, contains(notificationIdForTask('b')));
});
```

- [ ] **Step 5: Add backend protocol tests**

```go
func TestPostSyncRejectsUserWithoutEditPermission(t *testing.T) {
	res := performSyncRequest(t, ownerOnlyNoteID, nonOwnerToken, update)
	require.Equal(t, http.StatusForbidden, res.Code)
}

func TestLargeUpdateIsPersistedOnce(t *testing.T) {
	require.NoError(t, svc.ApplyNodeMutation(ctx, noteID, bytes.Repeat([]byte{1}, 6001)))
	require.Equal(t, 1, countYjsUpdates(t, ctx, pool, noteID))
}
```

- [ ] **Step 6: Run the focused characterization suites**

Run: `flutter test test/sync/editor_bridge_test.dart test/core/sync/yjs_sync_manager_test.dart test/features/notes/domain/yjs_task_command_test.dart test/core/sync/sync_service_note_exchange_test.dart test/features/tasks/domain/task_notification_reconciliation_test.dart`

Expected: only tests for interfaces not yet implemented fail; existing tests remain green.

- [ ] **Step 7: Commit the regression suite**

```bash
git add test backend/internal/sync
git commit -m "test(sync): characterize Yjs task and notification flows"
```

### Task 2: Introduce one YDoc task-command boundary and remove duplicate UI writes

**Files:**
- Create: `lib/features/tasks/domain/task_completion_command.dart`
- Modify: `lib/features/notes/domain/yjs_doc_editor_bridge.dart:230-284`
- Modify: `lib/features/notes/presentation/controllers/note_editor_controller.dart:79-102`
- Modify: `lib/features/notes/presentation/widgets/note_editor.dart:110-118`
- Modify: `lib/features/notes/presentation/widgets/custom_task_component.dart:52-89`
- Modify: `lib/features/notes/presentation/note_editor_screen.dart:183-217`
- Modify: `lib/features/tasks/presentation/controllers/task_snackbar_helper.dart`
- Test: `test/features/notes/domain/yjs_task_command_test.dart`
- Test: `test/features/notes/presentation/note_editor_screen_test.dart`

**Interfaces:**
- Consumes: the characterization contract from Task 1.
- Produces: `TaskCompletionCommand.complete(TaskSnapshot task, DateTime now)` and `YjsDocEditorBridge.applyTaskCommand(String nodeId, TaskCompletionCommand command)`.

- [ ] **Step 1: Define the pure recurrence command before mutating Yjs**

```dart
class TaskCompletionCommand {
  const TaskCompletionCommand(this._clock);
  final DateTime Function() _clock;

  TaskCompletionResult complete(TaskSnapshot task) {
    final completedAt = _clock().toUtc();
    final nextDue = task.recurrence == null
        ? null
        : nextDueDate(from: task.dueDate ?? completedAt, recurrence: task.recurrence!);
    return TaskCompletionResult(
      completed: nextDue == null,
      nextDue: nextDue,
      completedAt: completedAt,
      previousDue: task.dueDate,
      previousHasTime: task.hasTime,
    );
  }
}
```

- [ ] **Step 2: Run the pure command tests**

Run: `flutter test test/features/notes/domain/yjs_task_command_test.dart`

Expected: FAIL until `TaskSnapshot`, `TaskCompletionResult`, and `TaskCompletionCommand` exist.

- [ ] **Step 3: Apply the complete command in one Yjs transaction**

```dart
TaskCompletionResult completeTaskInYDoc(String nodeId, {DateTime? now}) {
  final nodeMap = _requireTaskNode(nodeId);
  final result = _taskCompletionCommand.complete(_readTaskSnapshot(nodeId, nodeMap, now));
  _doc.transact((_) {
    nodeMap.set('completed', result.completed);
    nodeMap.set('lastCompletedAt', result.completedAt.toIso8601String());
    if (result.nextDue == null) {
      nodeMap.delete('dueDate');
    } else {
      nodeMap.set('dueDate', _formatDueDate(result.nextDue!, hasTime: result.previousHasTime));
    }
  });
  _onDocChanged?.call();
  return result;
}
```

- [ ] **Step 4: Route all checkbox completion, undo, recurrence and metadata actions through the controller bridge**

```dart
final result = controller.completeTaskInYDoc(taskId);
TaskSnackBarHelper.showCompletion(result: result, onUndo: () {
  controller.reopenTaskInYDoc(taskId, previousDue: result.previousDue);
});
```

Delete the call sites that invoke `tasksRepositoryProvider.completeTask`, `reopenTask`, `TasksDao.completeTask`, or `TaskCompletionsDao.undoLastCompletion` from editor UI code.

- [ ] **Step 5: Remove the duplicate recurring callback**

`NoteEditor` must delegate exactly one completion action. Delete `onRecurringTaskComplete` after the unified completion result is used; it must not call `controller.completeRecurringTask` and a screen callback for the same tap.

- [ ] **Step 6: Run focused UI and command tests**

Run: `flutter test test/features/notes/domain/yjs_task_command_test.dart test/sync/editor_bridge_test.dart test/features/notes/presentation/note_editor_screen_test.dart test/core/database/daos/tasks_dao_test.dart`

Expected: PASS. The DAO tests remain for legacy batch/admin behavior only, not editor behavior.

- [ ] **Step 7: Commit the canonical task command**

```bash
git add lib/features/notes lib/features/tasks test/features/notes test/sync
git commit -m "refactor(tasks): mutate editor tasks through Yjs only"
```

### Task 3: Coalesce editor-to-YDoc changes and normalize the Yjs node schema

**Files:**
- Modify: `lib/features/notes/domain/editor_document_sync_manager.dart:42-297`
- Modify: `lib/features/notes/domain/yjs_doc_editor_bridge.dart:29-169`
- Modify: `lib/features/notes/domain/yjs_node_codec.dart`
- Modify: `lib/features/notes/domain/node_codec.dart`
- Create: `lib/features/notes/domain/yjs_note_schema.dart`
- Test: `test/sync/editor_bridge_test.dart`
- Test: `test/features/notes/domain/yjs_sync_fuzz_test.dart`
- Test: `test/features/notes/domain/yjs_schema_migration_test.dart`

**Interfaces:**
- Consumes: `TaskCompletionCommand` writes nested metadata from Task 2.
- Produces: `YjsNoteSchema.readNode`, `writeNode`, `normalizeNode`, and a bridge callback `void Function(Set<String> nodeIds) onDocCommitted`.

- [ ] **Step 1: Write schema compatibility tests**

```dart
test('normalization preserves legacy text and moves task metadata inside node map', () {
  final doc = legacyDocumentWithCompositeTaskFields();

  YjsNoteSchema.normalizeNode(doc, 'task-1');

  final node = YjsNoteSchema.requireNode(doc, 'task-1');
  expect(node.get('dueDate'), '2026-07-19T09:00');
  expect(doc.getMap<Object>('nodes')!.get('task-1:dueDate'), isNull);
  expect(doc.getText('content/task-1')!.toString(), 'Buy milk');
});
```

- [ ] **Step 2: Run the schema test before implementation**

Run: `flutter test test/features/notes/domain/yjs_schema_migration_test.dart`

Expected: FAIL because `YjsNoteSchema` does not exist.

- [ ] **Step 3: Add a focused schema module**

```dart
abstract final class YjsNoteSchema {
  static const nodesRoot = 'nodes';
  static String contentRoot(String id) => 'content/$id';

  static YMap requireNode(Doc doc, String id) { /* validate type == task/node */ }
  static void writeNode(Doc doc, DocumentNode node, {required String position}) { /* one canonical shape */ }
  static void normalizeNode(Doc doc, String id) { /* compatibility read, rewrite on touch */ }
}
```

The canonical node map stores `id`, `type`, `position`, `createdAt`, optional task fields, and non-text attributes. It must not store `data.text`, JSON node blobs, or top-level composite task keys. `content/<id>` remains the canonical `YText` root.

- [ ] **Step 4: Coalesce observer notifications once per transaction**

```dart
void _scheduleRemoteApply(Set<String> changedIds) {
  _pendingRemoteIds.addAll(changedIds);
  if (_remoteApplyQueued) return;
  _remoteApplyQueued = true;
  scheduleMicrotask(() {
    _remoteApplyQueued = false;
    final ids = {..._pendingRemoteIds};
    _pendingRemoteIds.clear();
    _applyChangedNodes(ids);
  });
}
```

Use the YMap observer for structural keys and the transaction observer for `YText` changes, but route both to `_scheduleRemoteApply`. Remove the unused `changedKeys` parameter and prohibit a full `noteNodesFromDoc()` decode for a single-node change.

- [ ] **Step 5: Compact local edit operations before serialization**

Replace the append-only `_pendingOps` list with a map keyed by node ID. Preserve the final structural operation and latest node snapshot, so typing 50 characters flushes one `UpdateOp`, not 50 serializations.

- [ ] **Step 6: Run schema, bridge, fuzz and analyzer checks**

Run: `flutter test test/sync/editor_bridge_test.dart test/features/notes/domain/yjs_schema_migration_test.dart test/features/notes/domain/yjs_sync_fuzz_test.dart`

Expected: PASS, including selection preservation and no duplicate remote application per transaction.

Run: `dart analyze lib/features/notes/domain test/sync`

Expected: `No issues found!`

- [ ] **Step 7: Commit the schema and observer consolidation**

```bash
git add lib/features/notes/domain test/sync test/features/notes/domain
git commit -m "refactor(yjs): normalize node schema and coalesce bridge updates"
```

### Task 4: Make local projection incremental, serial and side-effect free

**Files:**
- Modify: `lib/core/sync/yjs_sync_manager.dart:59-228`
- Modify: `lib/features/notes/presentation/controllers/note_editor_provider.dart:30-84`
- Modify: `lib/core/database/tables/local_yjs_states.dart`
- Modify: `lib/core/database/database.dart`
- Test: `test/core/sync/yjs_sync_manager_test.dart`
- Test: `test/core/sync/yjs_sync_manager_title_test.dart`
- Test: `test/core/database/daos/tasks_dao_test.dart`

**Interfaces:**
- Consumes: changed node IDs from Task 3.
- Produces: `Future<void> projectNodes(String noteId, {required Set<String> changedNodeIds, required bool markDirty})` and persisted `syncedStateVector` metadata for Task 5.

- [ ] **Step 1: Add projection no-op and complexity tests**

```dart
test('projecting an unchanged document performs no task writes', () async {
  await manager.projectNodes('note-1', changedNodeIds: {'task-1'}, markDirty: true);
  db.taskWriteCounter.reset();

  await manager.projectNodes('note-1', changedNodeIds: {'task-1'}, markDirty: true);

  expect(db.taskWriteCounter.value, 0);
});
```

- [ ] **Step 2: Run the projection test before implementation**

Run: `flutter test test/core/sync/yjs_sync_manager_test.dart`

Expected: FAIL because the projection always scans and compares every task.

- [ ] **Step 3: Replace repeated list scans with indexed reconciliation**

```dart
final existingById = {for (final row in existingRows) row.id: row};
for (final task in projectedTasks) {
  final existing = existingById.remove(task.id.value);
  if (existing == null) {
    batch.insert(_db.tasks, task);
  } else if (!sameProjectedTask(existing, task)) {
    batch.update(_db.tasks, preserveCreatedAt(task, existing));
  }
}
for (final orphan in existingById.values) {
  batch.delete(_db.tasks, orphan);
}
```

- [ ] **Step 4: Serialize projection and persistence per note**

Use `Map<String, Future<void>> _noteWriteChains`, enqueue work by note ID, and remove the unconditional `Future.delayed(10ms)`. A new projection supersedes an older pending projection for the same note by merging its changed IDs.

- [ ] **Step 5: Extend local state metadata**

Add nullable `BlobColumn get syncedStateVector` to `LocalYjsStates` and bump the Drift schema migration. It stores the vector only after a successful server exchange; it is not a second source of document content.

- [ ] **Step 6: Run projection tests and database migration tests**

Run: `flutter test test/core/sync/yjs_sync_manager_test.dart test/core/sync/yjs_sync_manager_title_test.dart test/core/database/daos/tasks_dao_test.dart`

Expected: PASS.

- [ ] **Step 7: Commit the local projection change**

```bash
git add lib/core/sync lib/core/database lib/features/notes/presentation/controllers test/core
git commit -m "perf(sync): coalesce Yjs projections and index task reconciliation"
```

### Task 5: Unify sync around authenticated per-note state-vector exchange

**Files:**
- Modify: `lib/core/sync/sync_service.dart`
- Modify: `lib/core/sync/sync_mapper.dart`
- Modify: `backend/internal/sync/rest_handler.go`
- Modify: `backend/internal/sync/service.go`
- Modify: `backend/internal/sync/repository.go`
- Modify: `backend/cmd/server/main.go`
- Test: `test/core/sync/sync_service_note_exchange_test.dart`
- Test: `test/core/sync/sync_service_test.dart`
- Test: `backend/internal/sync/protocol_test.go`
- Test: `backend/internal/sync/service_test.go`

**Interfaces:**
- Consumes: `LocalYjsState.syncedStateVector` from Task 4.
- Produces: `Future<void> SyncService.syncDirtyNote(String noteId)` and an authenticated Go `PostSyncHandler` authorization dependency.

- [ ] **Step 1: Test an unauthorized note sync and idle second exchange**

Run: `flutter test test/core/sync/sync_service_note_exchange_test.dart`

Expected: FAIL until the service performs a per-note exchange and persists the server vector.

Run: `go test ./internal/sync -run 'Test(PostSyncRejectsUserWithoutEditPermission|LargeUpdateIsPersistedOnce|SyncProtocol)' -count=1`

Expected: FAIL until the handler authorizes the note and removes duplicate persistence.

- [ ] **Step 2: Authorize the binary endpoint before reading or applying the update**

```go
type NoteAuthorizer interface {
	CanEditNote(ctx context.Context, noteID, userID pgtype.UUID) (bool, error)
}

func PostSyncHandler(ydocSvc *YDocService, authorizer NoteAuthorizer) echo.HandlerFunc {
	return func(c echo.Context) error {
		userID := web.CurrentUserID(c)
		noteID, err := parseUUIDStr(c.Param("id"))
		if err != nil { return web.JSONError(c, http.StatusBadRequest, "invalid note id") }
		allowed, err := authorizer.CanEditNote(c.Request().Context(), noteID, userID)
		if err != nil { return web.JSONError(c, http.StatusInternalServerError, "authorization failed") }
		if !allowed { return web.JSONError(c, http.StatusForbidden, "note is not editable") }
		// Existing binary state-vector exchange follows.
	}
}
```

Use the project's actual authenticated-user helper when implementing; do not trust a user ID supplied by the request body or header.

- [ ] **Step 3: Exchange only the local diff and persist the final vector**

```dart
Future<void> syncDirtyNote(String noteId) => _noteSyncChains.enqueue(noteId, () async {
  final doc = await _yjsMgr.loadDoc(noteId);
  final persisted = await _yjsMgr.localState(noteId);
  final localUpdate = encodeStateAsUpdate(doc, persisted.syncedStateVector);
  if (localUpdate.isEmpty) return;

  final response = await _noteTransport.exchange(noteId, localUpdate, encodeStateVector(doc));
  if (response.isNotEmpty) applyUpdate(doc, response);
  await _yjsMgr.persistWithSyncedVector(noteId, encodeStateVector(doc));
});
```

- [ ] **Step 4: Replace the background full-snapshot Yjs payload**

Keep `/sync/push` for relational metadata such as note creation, links, tags and preferences. After it succeeds, iterate dirty Yjs note IDs through `syncDirtyNote` with bounded concurrency of two. Remove `note_yjs_states` from the client push payload once all supported app versions use the binary endpoint.

- [ ] **Step 5: Remove polling overlap and log payload metadata only**

Replace the active-note periodic fire-and-forget call with the same per-note queue and a change debounce. Flush it on `onPause`, `onInactive`, editor disposal and connectivity restoration. Log note ID only as a hashed/debug-safe identifier and byte counts, never document content.

- [ ] **Step 6: Remove duplicate large-update persistence in Go**

Delete the second `persistNoteToDB` call in the `len(update) >= 6000` branch. The first synchronous persistence is sufficient for another instance to load the state after receiving an empty-payload `NOTIFY`.

- [ ] **Step 7: Run sync verification**

Run: `flutter test test/core/sync/sync_service_note_exchange_test.dart test/core/sync/sync_service_test.dart`

Expected: PASS.

Run: `go test ./internal/sync -count=1`

Expected: PASS.

- [ ] **Step 8: Commit the transport change**

```bash
git add lib/core/sync lib/core/database backend/internal/sync backend/cmd/server test/core/sync
git commit -m "refactor(sync): exchange Yjs changes through authorized note diffs"
```

### Task 6: Bound backend YDoc memory and make projection work observable

**Files:**
- Modify: `backend/internal/sync/ydoc_service.go`
- Modify: `backend/internal/sync/compactor.go`
- Modify: `backend/internal/sync/projection.go`
- Modify: `backend/internal/sync/task_projection.go`
- Test: `backend/internal/sync/ydoc_service_unit_test.go`
- Test: `backend/internal/sync/compactor_integration_test.go`
- Test: `backend/internal/sync/projection_integration_test.go`

**Interfaces:**
- Consumes: authenticated and incremental updates from Task 5.
- Produces: bounded `YDocService` cache and projection metrics tagged only by duration/count/bytes.

- [ ] **Step 1: Add cache eviction and fallback-root tests**

```go
func TestYDocServiceEvictsLeastRecentlyUsedIdleDocument(t *testing.T) {
	svc := NewYDocService(pool, projection, "test", WithMaxCachedDocs(2))
	loadDocs(t, svc, "n1", "n2", "n3")
	require.NotContains(t, svc.docs, "n1")
}

func TestPreRegisterYTextRecognizesFixedAndCanonicalRoots(t *testing.T) {
	// update contains content/a and content_fixed/b; both must decode as YText.
}
```

- [ ] **Step 2: Run the backend cache tests before implementation**

Run: `go test ./internal/sync -run 'Test(YDocServiceEvicts|PreRegisterYText)' -count=1`

Expected: FAIL because the cache is unbounded and the regex only recognizes `content/`.

- [ ] **Step 3: Implement bounded LRU/TTL cache and lock cleanup**

```go
type cachedDoc struct { doc *crdt.Doc; lastUsed time.Time }

func (s *YDocService) evictIdleLocked(now time.Time) {
	for id, entry := range s.docs {
		if len(s.docs) > s.maxCachedDocs || now.Sub(entry.lastUsed) > s.idleTTL {
			delete(s.docs, id)
			delete(s.docLocks, id)
		}
	}
}
```

Run eviction only while holding the cache/lock-map mutexes in a consistent order. Do not evict a document currently protected by its per-note lock.

- [ ] **Step 4: Make fallback recognition explicitly temporary**

Change the pre-registration matcher to recognize both `content/<uuid>` and `content_fixed/<uuid>`. Add a structured counter for legacy-root reads; remove the fallback only after the migration gate from this plan is satisfied.

- [ ] **Step 5: Remove per-note debounce map entries after execution**

After a projection timer fires and verifies its sequence, delete the corresponding debounce entry if it has no newer timer. This bounds the map by active notes rather than all historical notes.

- [ ] **Step 6: Run backend projection and compactor suites**

Run: `go test ./internal/sync -count=1`

Expected: PASS.

- [ ] **Step 7: Commit backend lifecycle changes**

```bash
git add backend/internal/sync
git commit -m "perf(sync): bound YDoc cache and projection scheduler state"
```

### Task 7: Reconcile notifications deterministically per user

**Files:**
- Create: `lib/features/tasks/domain/task_notification_id.dart`
- Modify: `lib/features/tasks/domain/task_notification_scheduler.dart`
- Modify: `lib/core/notifications/local_notification_service.dart`
- Modify: `lib/main.dart`
- Test: `test/features/tasks/domain/task_notification_reconciliation_test.dart`
- Test: `test/features/tasks/domain/task_notification_scheduler_test.dart`

**Interfaces:**
- Consumes: the user-scoped task projection from Task 4.
- Produces: `Future<void> TaskNotificationScheduler.reconcile({required String userId, required List<TaskData> tasks})` and `int notificationIdForTask(String userId, String taskId)`.

- [ ] **Step 1: Write failure tests for account switch, overlap and ID collision handling**

```dart
test('concurrent stream emissions converge to the newest desired schedule', () async {
  final first = scheduler.reconcile(userId: 'u1', tasks: [task('a')]);
  final second = scheduler.reconcile(userId: 'u1', tasks: [task('b')]);
  await Future.wait([first, second]);

  expect(plugin.pendingIds, [notificationIdForTask('u1', 'b')]);
});
```

- [ ] **Step 2: Run notification tests before implementation**

Run: `flutter test test/features/tasks/domain/task_notification_reconciliation_test.dart test/features/tasks/domain/task_notification_scheduler_test.dart`

Expected: FAIL because reconciliation is not serialized or user-scoped.

- [ ] **Step 3: Introduce deterministic notification IDs**

```dart
int notificationIdForTask(String userId, String taskId) {
  final bytes = utf8.encode('$userId:$taskId');
  return crc32(bytes) & 0x7fffffff;
}
```

Store the user/task mapping in a small Drift table if a collision is detected; never use `String.hashCode` as a persisted platform ID.

- [ ] **Step 4: Serialize and reconcile the desired schedule**

```dart
Future<void> reconcile({required String userId, required List<TaskData> tasks}) {
  _reconcileChain = _reconcileChain.then((_) => _reconcileNow(userId, tasks));
  return _reconcileChain;
}
```

`_reconcileNow` must read platform pending notifications, cancel IDs absent from the desired user-scoped set, schedule only changed dates, and write the cache under `task_notification_schedule_cache:<userId>`. It must cancel the old user's entries on auth transition.

- [ ] **Step 5: Remove artificial delays and request permission on intent**

Delete the 100 ms delay between schedules. Request platform notification permission when a user first saves a non-null reminder, not in `main()` startup. Preserve a non-blocking fallback when permission is denied.

- [ ] **Step 6: Run notification tests and analyzer**

Run: `flutter test test/features/tasks/domain/task_notification_reconciliation_test.dart test/features/tasks/domain/task_notification_scheduler_test.dart`

Expected: PASS.

Run: `dart analyze lib/features/tasks/domain lib/core/notifications test/features/tasks/domain`

Expected: `No issues found!`

- [ ] **Step 7: Commit notification reconciliation**

```bash
git add lib/features/tasks/domain lib/core/notifications lib/main.dart test/features/tasks/domain
git commit -m "refactor(notifications): reconcile task reminders per user"
```

### Task 8: Remove superseded code and complete the compatibility migration

**Files:**
- Delete: `lib/core/sync/yjs_sync_protocol_codec.dart`
- Delete: `lib/core/sync/sync_repository.dart`
- Delete: `lib/features/tasks/presentation/controllers/task_controller.dart`
- Modify: `lib/core/sync/yjs_sync_manager.dart`
- Modify: `lib/features/tasks/data/tasks_repository.dart`
- Modify: `lib/features/tasks/data/local/tasks_local_repository.dart`
- Modify: `lib/core/database/daos/tasks_dao.dart`
- Modify: `lib/features/notes/domain/yjs_node_codec.dart`
- Modify: `backend/internal/sync/projection.go`
- Test: all tests named in Tasks 1-7

**Interfaces:**
- Consumes: migration metrics and passing compatibility tests from Tasks 3 and 6.
- Produces: one active implementation for Yjs sync, task mutation, and notification scheduling.

- [ ] **Step 1: Verify all replacement call sites exist**

Run: `rg -n "tasksRepositoryProvider\).*\.(completeTask|reopenTask)|TaskCompletionsDao.*undoLastCompletion|completeRecurringTask|YjsSyncProtocolCodec|TaskController|projectState\(" lib test`

Expected: no editor UI call to direct task mutation; only explicitly documented batch/admin paths may remain.

- [ ] **Step 2: Delete unreachable wrappers and obsolete protocol code**

Delete `yjs_sync_protocol_codec.dart`, empty `sync_repository.dart`, and `TaskController` only after `rg` confirms they have no production consumers. Delete `YjsSyncManager.projectState` if no callers remain after the incremental projection API is live.

- [ ] **Step 3: Restrict legacy DAO methods to non-UI batch maintenance**

Remove public repository methods for direct `createTask`, `updateTask`, `completeTask`, `reopenTask`, and reorder mutations if no non-editor feature requires them. If a batch/admin caller still needs one, move it behind a clearly named maintenance interface that is not imported by presentation code.

- [ ] **Step 4: Remove legacy Yjs readers only after the fleet gate**

Delete support for JSON-string nodes, `data.text`, composite task keys, and `content_fixed` only after the server metric remains zero for one release-retention window. In the same commit, delete their compatibility tests and retain canonical-schema convergence tests.

- [ ] **Step 5: Run full verification**

Run: `flutter test`

Expected: PASS.

Run: `dart analyze lib test`

Expected: `No issues found!`

Run: `go test ./...`

Expected: PASS.

- [ ] **Step 6: Commit cleanup**

```bash
git add -A
git commit -m "chore(sync): remove superseded Yjs and task mutation paths"
```

## Rollout and observability checklist

- [ ] Ship Tasks 1-4 behind no behavior flag; they retain wire compatibility.
- [ ] Ship Task 5 with the old batch `note_yjs_states` reader retained for one supported app-version window.
- [ ] Measure: Yjs update bytes, note-exchange count, projection duration, projection coalescing ratio, backend cached-doc count, cache eviction count, legacy-schema read count, notification reconcile duration and pending notification count.
- [ ] Alert on Yjs decode failure, projection failure, unauthorized binary sync attempt, or a legacy-root read after the migration deadline.
- [ ] Enable Task 8 only when legacy schema metrics are zero and all supported clients use the per-note endpoint.

## Self-review

**Spec coverage:** The plan covers editor conversion, Yjs schema, local persistence/projection, active and background sync, Go persistence/notification, task date/time/recurrence/reminder commands, platform notifications, test gaps, performance work, and removal of unused/legacy code.

**Placeholder scan:** No implementation task contains an unbounded "handle errors" instruction; each has concrete files, contract, test command and expected result.

**Type consistency:** `TaskCompletionCommand` returns `TaskCompletionResult`; the bridge owns `completeTaskInYDoc`; `YjsSyncManager` owns projection and persisted sync vector; `SyncService` owns `syncDirtyNote`; `TaskNotificationScheduler` owns `reconcile`.

# Tasks independentes e abas Tasks/Notas — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar tasks independentes, sincronizadas entre dispositivos do proprietário, e uma navegação com Tasks e Notas que agrega opcionalmente as tasks dos documentos.

**Architecture:** Tasks independentes terão uma entidade PostgreSQL/Drift, outbox e protocolo idempotente próprio. Tasks de notas continuarão nos documentos REST/OT; um provider local combinará as duas fontes para a lista e o histórico, sem persistir um terceiro modelo. O feed existente ganhará escopo compatível para clientes antigos e bootstrap versionado para tasks.

**Tech Stack:** Flutter, Riverpod manual, Drift, Go, Echo, PostgreSQL, sqlc, Dio, go_router, Super Editor e `TaskOccurrencePolicy`.

**Spec:** `docs/superpowers/specs/2026-09-03-standalone-tasks-tabs-design.md`

## Global Constraints

- O documento REST/OT continua sendo a fonte de verdade somente para tasks que são blocos de uma nota.
- A tabela local `tasks` pertence exclusivamente às tasks independentes; não é projeção de `TaskNode`.
- Tasks de nota e tasks independentes são combinadas somente no provider de leitura da tela.
- Providers são manuais e `.autoDispose`; streams Drift não usam `.first` em `build()`.
- Cada mutação independente usa `operationId`, hash de payload e resposta idempotente.
- Clientes antigos continuam recebendo somente eventos de nota; clientes novos optam por `scope=all`.
- `bootstrapVersion = 2` só é gravado depois de notas e tasks serem carregadas na mesma transação local.
- Tasks de nota não recebem escritas na tabela independente.
- Exclusão independente usa tombstone; payloads de ocorrências carregam `scheduleGeneration`.
- Notas excluídas, revogadas ou sem documento efetivo não entram na agregação.
- Não serão adicionados testes que validem geometria, pixels ou aparência visual.
- Strings simples ficam inline; mensagens longas e reutilizadas ficam em constantes da feature.
- Handlers Go permanecem finos e todas as rotas usam o prefixo `/api/v1/`.
- O app nunca apaga o banco local do usuário como estratégia de migração.

---

## File Map

### Flutter — contratos, banco e sync

- Create `lib/features/tasks/domain/standalone_task.dart`: modelo canônico independente e codec JSON.
- Create `lib/features/tasks/domain/standalone_task_operation.dart`: tipos e payloads idempotentes.
- Create `lib/features/tasks/domain/task_list_item.dart`: DTO de apresentação discriminado por origem.
- Create `lib/features/tasks/domain/task_history_entry.dart`: DTO de histórico.
- Create `lib/core/database/tables/standalone_tasks.dart`: tabelas Drift `StandaloneTasks` e `PendingTaskOperations`.
- Create `lib/core/database/daos/standalone_tasks_dao.dart`: queries transacionais e streams por usuário.
- Create `lib/features/tasks/data/standalone_task_api.dart`: contrato HTTP com `/tasks` e `/tasks/:id/mutations`.
- Create `lib/features/tasks/data/standalone_task_repository.dart`: mutações locais, outbox e leitura.
- Create `lib/features/tasks/data/standalone_task_sync_service.dart`: envio serializado e confirmação por `operationId`.
- Create `lib/core/sync/standalone_task_outbox_worker.dart`: retry e backoff por task.
- Modify `lib/core/database/database.dart`, `lib/core/sync/sync_inbox_store.dart`, `lib/core/database/tables/sync_inbox.dart`, `lib/core/database/tables/sync_feed_cursors.dart`, `lib/core/sync/sync_feed_client.dart` and `lib/core/sync/note_remote_sync_coordinator.dart` for schema, events and bootstrap.
- Modify `lib/core/di/providers.dart` and `lib/core/sync/note_remote_sync_runtime.dart` for authenticated-session lifecycle.

### Flutter — agregação, notificações e UI

- Create `lib/features/tasks/domain/note_task_list_reader.dart`: task reader for lists, separate from notification reader.
- Create `lib/features/tasks/application/task_list_providers.dart`: streams, filter, temporal clock and history.
- Create `lib/features/tasks/application/standalone_task_controller.dart`: create, edit, complete, reopen and delete.
- Create `lib/features/tasks/presentation/tasks_screen.dart`: main list and note-task toggle.
- Create `lib/features/tasks/presentation/completed_tasks_screen.dart`: history.
- Create `lib/features/tasks/presentation/standalone_task_editor_screen.dart`: standalone edit-only screen.
- Create `lib/features/tasks/presentation/widgets/task_list_tile.dart`, `task_source_label.dart`, `completed_tasks_tile.dart` and `standalone_task_form.dart`.
- Create `lib/shared/widgets/app_navigation_shell.dart`: public shell for Tasks and Notas.
- Modify `lib/core/router/app_routes.dart`, `lib/core/router/app_router.dart` and `lib/features/notes/editor/presentation/note_editor_screen.dart` for tabs, routes and `blockId`.
- Modify `lib/features/tasks/domain/task_notification_id.dart`, `task_notification_scheduler.dart` and `note_task_notification_source.dart` for both sources and collision-free IDs.

### Go — schema, API and feed

- Create `backend/db/migrations/000055_standalone_tasks.up.sql` and `.down.sql`: legacy quarantine, independent tables and feed columns.
- Create `backend/db/queries/tasks.sql`: bootstrap, reads, operation log and transactional persistence.
- Create `backend/internal/tasks/contract.go`, `repository.go`, `service.go`, `handler.go` and focused tests.
- Modify `backend/internal/syncfeed/repository.go`, `handler.go`, tests and generated `backend/internal/db/sqlcgen/*` for `scope` and `taskId`.
- Modify `backend/cmd/server/main.go` to register `/api/v1/tasks` and inject the service.

### Documentation and tests

- Modify `AGENTS.md`, `CONTEXT.md`, `lib/features/tasks/README.md`, `docs/architecture/backend-file-reference.md` and `docs/operations/task-document-migration-runbook.md` to remove the obsolete projection claim and document quarantine.
- Create focused tests under `test/features/tasks/domain`, `test/features/tasks/data`, `test/features/tasks/application`, `test/features/tasks/presentation` and `test/core/sync`.
- Modify existing sync contract tests only where event fields or scope require it; do not add visual-layout assertions.

---

### Task 1: Congelar os contratos de domínio e o protocolo de operações

**Files:**
- Create: `lib/features/tasks/domain/standalone_task.dart`
- Create: `lib/features/tasks/domain/standalone_task_operation.dart`
- Create: `lib/features/tasks/domain/task_list_item.dart`
- Create: `lib/features/tasks/domain/task_history_entry.dart`
- Test: `test/features/tasks/domain/standalone_task_test.dart`
- Test: `test/features/tasks/domain/standalone_task_operation_test.dart`

**Interfaces:**
- Produces `StandaloneTask`, `StandaloneTask.fromJson`, `StandaloneTask.toJson`, `StandaloneTask.copyWith`, `StandaloneTask.scheduleGeneration`.
- Produces `StandaloneTaskOperation.create`, `.upsert`, `.completeOccurrence`, `.reopenOccurrence`, `.delete`, with `operationId`, `taskId`, `observedRevision`, `scheduleGeneration`, `payload` and `payloadHash`.
- Produces `TaskListItem.standalone`, `TaskListItem.note` and `TaskHistoryEntry`.

- [ ] **Step 1: Write failing canonical JSON and generation tests.**

```dart
test('round trips a standalone task without losing completions', () {
  final task = fixtureRecurringTask(
    completions: {'2026-09-15T09:00:00.000': '2026-09-14T12:00:00.000Z'},
  );
  expect(StandaloneTask.fromJson(task.toJson()), task);
});

test('schedule metadata changes clear history and increment generation', () {
  final task = fixtureRecurringTask(
    completions: {'2026-09-15T09:00:00.000': '2026-09-14T12:00:00.000Z'},
  );
  final changed = task.withSchedule(
    dueDate: DateTime.utc(2026, 9, 16, 9),
    hasTime: true,
    recurrenceRule: 'weekly',
  );
  expect(changed.scheduleGeneration, task.scheduleGeneration + 1);
  expect(changed.completions, isEmpty);
});
```

Run: `flutter test test/features/tasks/domain/standalone_task_test.dart test/features/tasks/domain/standalone_task_operation_test.dart`

Expected: FAIL with unresolved `StandaloneTask` and `StandaloneTaskOperation` symbols.

- [ ] **Step 2: Implement immutable contracts and deterministic payload hashes.**

Use UTC ISO-8601 for instants, wall-clock canonical keys for `scheduledAt`, sorted-key JSON for hashes, and `FormatException` for empty titles or invalid generation values.

- [ ] **Step 3: Run the focused tests and add idempotency edge cases.**

Run: `flutter test test/features/tasks/domain/standalone_task_test.dart test/features/tasks/domain/standalone_task_operation_test.dart`

Expected: PASS for round trips, generation changes, same-payload same-hash and changed-payload different-hash.

- [ ] **Step 4: Commit the domain contract.**

```powershell
git add lib/features/tasks/domain test/features/tasks/domain
git commit -m "feat(tasks): define standalone task contracts"
```

### Task 2: Criar a migração PostgreSQL e a quarentena do schema legado

**Files:**
- Create: `backend/db/migrations/000055_standalone_tasks.up.sql`
- Create: `backend/db/migrations/000055_standalone_tasks.down.sql`
- Test: `backend/internal/tasks/migration_test.go`

**Interfaces:**
- Produces tables `tasks`, `task_operations` and feed column `task_id`.
- Produces a migration invariant: old rows are renamed to `tasks_legacy_quarantine_v31` and `task_completions_legacy_quarantine_v31`; no legacy row is promoted.

- [ ] **Step 1: Write the migration contract test.**

Create the old schema with zero rows, apply all migrations, assert new columns `owner_user_id`, `completions`, `schedule_generation` and `deleted_at`, then assert `task_operations` has `operation_id`, `payload_hash` and `response_json`.

Run: `go test ./internal/tasks -run TestStandaloneTaskMigration -v`

Expected: FAIL because migration `000055` and the package do not exist.

- [ ] **Step 2: Add the atomic up migration.**

Rename physical legacy tables before creating the new `tasks`; create `task_operations` with `(task_id, operation_id)` uniqueness and payload hash; add owner/deleted/agenda indexes; extend `sync_changes` with nullable `task_id` and `task_changed`/`task_deleted` kinds. Do not drop the legacy tables.

- [ ] **Step 3: Add the guarded down migration.**

Allow rollback only while new `tasks` and `task_operations` are empty. Drop the new schema, restore quarantine names and restore the prior feed shape; raise before changing anything if new data exists.

- [ ] **Step 4: Run empty and non-empty legacy migration tests.**

Run: `go test ./internal/tasks -run TestStandaloneTaskMigration -v`

Expected: PASS for empty legacy tables, preservation of legacy rows in quarantine, and a guarded-down failure after inserting a new task.

- [ ] **Step 5: Commit the database contract.**

```powershell
git add backend/db/migrations backend/internal/tasks/migration_test.go
git commit -m "feat(tasks): add standalone task schema and quarantine"
```

### Task 3: Implementar o serviço Go de tasks e os endpoints

**Files:**
- Create: `backend/db/queries/tasks.sql`
- Create: `backend/internal/tasks/contract.go`
- Create: `backend/internal/tasks/repository.go`
- Create: `backend/internal/tasks/service.go`
- Create: `backend/internal/tasks/handler.go`
- Create: `backend/internal/tasks/service_test.go`
- Create: `backend/internal/tasks/handler_test.go`
- Modify: `backend/cmd/server/main.go`
- Generated: `backend/internal/db/sqlcgen/*` via `make -C backend sqlc`

**Interfaces:**
- `GET /api/v1/tasks/bootstrap` returns `{ "watermark": number, "tasks": [...] }` for the authenticated owner.
- `GET /api/v1/tasks/:id` returns the owner’s task or `404` without existence leakage.
- `POST /api/v1/tasks/:id/mutations` accepts `{operationId, observedRevision, scheduleGeneration, kind, payload}` and returns `{operationId, revision, task}`.
- `TaskService.ApplyMutation(ctx, userID, taskID, mutation) (MutationResult, error)` performs auth, validation, serialization, idempotency and feed emission.

- [ ] **Step 1: Write service tests for create, retry, hash mismatch and owner isolation.**

```go
func TestApplyMutationSameOperationReturnsOriginalResult(t *testing.T) {
    first := applyMutation(t, mutation("op-1", "upsert", map[string]any{"title": "A"}))
    second := applyMutation(t, mutation("op-1", "upsert", map[string]any{"title": "A"}))
    if first.Revision != second.Revision || first.Task.Title != second.Task.Title {
        t.Fatalf("retry changed the accepted result: first=%+v second=%+v", first, second)
    }
}
```

Run: `go test ./internal/tasks -run 'TestApplyMutation|TestTaskAuthorization' -v`

Expected: FAIL because service and repository are not defined.

- [ ] **Step 2: Define SQL queries and regenerate sqlc.**

Lock task rows during mutation, load `task_operations` by operation ID, insert canonical response JSON, update owner rows only, and return the task after incrementing revision. The bootstrap query must run in repeatable-read and return the task snapshot plus the current owner feed watermark.

- [ ] **Step 3: Implement validation and mutation semantics.**

Validate title, recurrence/reminder values, UTC instants and payload hash. Apply metadata patches in arrival order, merge completion keys, reject stale generation with `SCHEDULE_CHANGED`, reject tombstones with `TASK_DELETED`, and emit `sync_changes` in the same transaction.

- [ ] **Step 4: Implement Echo handlers and register protected routes.**

Use `web.UserID`, return `{ "error": "message" }`, map `SCHEDULE_CHANGED` to 409 and `TASK_DELETED` to 410, and never reveal another user’s task.

- [ ] **Step 5: Run backend tests and generated-code checks.**

Run: `go test ./internal/tasks ./internal/syncfeed -v`; `go vet ./...`; `make -C backend sqlc`.

Expected: PASS and no uncommitted generated-code drift.

- [ ] **Step 6: Commit the backend task API.**

```powershell
git add backend/db/queries backend/internal/tasks backend/internal/db/sqlcgen backend/cmd/server/main.go
git commit -m "feat(tasks): add standalone task API"
```

### Task 4: Tornar o feed compatível e adicionar bootstrap versionado

**Files:**
- Modify: `backend/internal/syncfeed/repository.go`
- Modify: `backend/internal/syncfeed/handler.go`
- Modify: `backend/internal/syncfeed/integration_test.go`
- Modify: `backend/internal/syncfeed/handler_test.go`
- Modify: `lib/core/sync/sync_feed_client.dart`
- Modify: `lib/core/database/tables/sync_inbox.dart`
- Modify: `lib/core/database/tables/sync_feed_cursors.dart`
- Modify: `lib/core/database/database.dart`
- Modify: `lib/core/sync/sync_inbox_store.dart`
- Modify: `lib/core/sync/note_remote_sync_coordinator.dart`
- Modify: `lib/features/notes/catalog/data/note_catalog_sync.dart` to separate remote fetch from the atomic local bootstrap write.
- Test: `test/core/sync/sync_feed_client_test.dart`
- Test: `test/core/sync/sync_inbox_store_test.dart`
- Test: `test/core/sync/note_remote_sync_coordinator_test.dart`

**Interfaces:**
- `SyncChange` gains nullable `taskId` and `SyncFeedClient.fetchChanges({after, limit, scope = SyncFeedScope.notes})`.
- `scope=notes` is the server default; `scope=all` includes task events.
- `SyncInboxEntry` stores `taskId`; task events do not require `noteId`.
- `SyncFeedCursors.bootstrapVersion` must equal `2` before `scope=all` is used.

- [ ] **Step 1: Write old/new scope contract tests.**

Test that `task_changed` without `noteId` parses when `taskId` is present, the client sends `scope=all` only when requested, and the server default excludes task rows.

Run: `flutter test test/core/sync/sync_feed_client_test.dart test/core/sync/sync_inbox_store_test.dart`; `go test ./internal/syncfeed -v`.

Expected: FAIL until fields, query filtering and storage columns exist.

- [ ] **Step 2: Add the feed fields without changing the schema version yet.**

Add `taskId` to `SyncInbox` and `bootstrapVersion` to `SyncFeedCursors` in the Drift declarations and generated types. Leave the physical migration and `schemaVersion` bump to Task 5, where the new task tables and all version-32 changes are applied atomically.

- [ ] **Step 3: Add server-side scope filtering.**

Update repository SQL to select notes for `scope=notes` and both resources for `scope=all`; retain the old default. Invalid scope returns 400.

- [ ] **Step 4: Implement resumable bootstrap.**

Read a watermark, fetch notes without committing them, fetch `GET /tasks/bootstrap`, then apply both snapshots plus cursor/version through one `AppDatabase.transaction`. Keep version below `2` after any failure. Start `scope=all` only at version `2`; a crash before the final transaction simply repeats the fetch.

- [ ] **Step 5: Add task event routing hooks.**

Add `bootstrapTasks`, `applyTaskChanged` and `applyTaskDeleted` callbacks to the coordinator. Preserve current note handling and keep unknown events pending with a protocol error.

- [ ] **Step 6: Run focused sync tests and commit.**

Run: `flutter test test/core/sync/sync_feed_client_test.dart test/core/sync/sync_inbox_store_test.dart test/core/sync/note_remote_sync_coordinator_test.dart`; `go test ./internal/syncfeed -v`.

Expected: PASS for old-client notes scope, new-client all scope, bootstrap retry, task routing and cursor monotonicity.

```powershell
git add backend/internal/syncfeed lib/core/sync lib/core/database test/core/sync backend/db/migrations
git commit -m "feat(sync): add compatible task feed scope"
```

### Task 5: Adicionar Drift, quarentena local e repositório offline-first

**Files:**
- Create: `lib/core/database/tables/standalone_tasks.dart`
- Create: `lib/core/database/daos/standalone_tasks_dao.dart`
- Create: `lib/features/tasks/data/standalone_task_repository.dart`
- Modify: `lib/core/database/database.dart`
- Modify: `lib/core/di/providers.dart`
- Test: `test/core/database/daos/standalone_tasks_dao_test.dart`
- Test: `test/features/tasks/data/standalone_task_repository_test.dart`

**Interfaces:**
- `StandaloneTasksDao.watchTasks(String userId) -> Stream<List<StandaloneTaskData>>`.
- `StandaloneTasksDao.watchTask(String userId, String taskId) -> Stream<StandaloneTaskData?>`.
- `StandaloneTasksDao.enqueueMutation(PendingTaskOperationsCompanion operation) -> Future<void>`.
- `StandaloneTaskRepository.create`, `.update`, `.completeOccurrence`, `.reopenOccurrence`, `.delete` update local task and outbox in one transaction.

- [ ] **Step 1: Write DAO and transaction tests.**

Test that a local create emits immediately, inserts exactly one pending operation, and a deletion leaves a tombstone. Test that `watchTasks` filters by owner and `deletedAt IS NULL`.

Run: `flutter test test/core/database/daos/standalone_tasks_dao_test.dart test/features/tasks/data/standalone_task_repository_test.dart`

Expected: FAIL because the Drift tables and DAO are not registered.

- [ ] **Step 2: Add Drift tables and register them in `AppDatabase`.**

Store `completions` as canonical JSON text locally, use indexes `(ownerUserId, deletedAt, dueDate)` and `(ownerUserId, updatedAt)`, and keep `operationId` as the outbox primary key with task ordering.

- [ ] **Step 3: Add schema 32 migration, feed-column migration and local quarantine.**

Set `schemaVersion` to `32`, rebuild `SyncInbox`/`SyncFeedCursors` with their new columns, then rename physical `tasks`, `task_completions` and `local_task_completions` leftovers to versioned quarantine names before creating the new Drift task tables. Never drop non-empty remnants, never clear note operations, and expose a diagnostic state so task-independent UI can remain unavailable without hiding note errors.

- [ ] **Step 4: Implement DAO queries and repository transactions.**

Generate operation IDs and payload hashes at the repository boundary; update local state optimistically; insert the outbox row in the same transaction; preserve later pending operations when a remote task is applied.

- [ ] **Step 5: Run Drift generation and focused tests.**

Run: `dart run build_runner build --delete-conflicting-outputs`; `flutter test test/core/database/daos/standalone_tasks_dao_test.dart test/features/tasks/data/standalone_task_repository_test.dart`.

Expected: PASS with schema 32 and no visual assertions.

- [ ] **Step 6: Commit local task persistence.**

```powershell
git add lib/core/database lib/features/tasks/data lib/core/di test/core/database test/features/tasks/data
git commit -m "feat(tasks): persist standalone tasks offline"
```

### Task 6: Implementar API Dart, outbox worker e confirmação idempotente

**Files:**
- Create: `lib/features/tasks/data/standalone_task_api.dart`
- Create: `lib/features/tasks/data/standalone_task_sync_service.dart`
- Create: `lib/core/sync/standalone_task_outbox_worker.dart`
- Modify: `lib/core/di/providers.dart`
- Modify: `lib/core/sync/note_remote_sync_runtime.dart`
- Test: `test/features/tasks/data/standalone_task_api_test.dart`
- Test: `test/features/tasks/data/standalone_task_sync_service_test.dart`
- Test: `test/core/sync/standalone_task_outbox_worker_test.dart`

**Interfaces:**
- `StandaloneTaskApi.bootstrap() -> Future<TaskBootstrapResponse>`.
- `StandaloneTaskApi.fetch(String taskId) -> Future<StandaloneTask>`.
- `StandaloneTaskApi.mutate(StandaloneTaskOperation operation) -> Future<TaskMutationResponse>`.
- `StandaloneTaskSyncService.syncTask(String taskId) -> Future<void>`.
- `StandaloneTaskOutboxWorker.drain() -> Future<void>` and `.wake({bool resetBackoff = true})`.

- [ ] **Step 1: Write API parsing tests.**

Cover bootstrap watermark, mutation response, `409 SCHEDULE_CHANGED`, `410 TASK_DELETED`, malformed payload and network failure mapping to the existing API exception convention.

Run: `flutter test test/features/tasks/data/standalone_task_api_test.dart`

Expected: FAIL because the API and response classes do not exist.

- [ ] **Step 2: Implement API methods through `ApiClient`.**

Use `/tasks/bootstrap`, `/tasks/:id` and `/tasks/:id/mutations`; preserve `{ "error": "message" }` parsing and never call Dio directly from widgets.

- [ ] **Step 3: Write sync ordering and confirmation tests.**

Enqueue create, title update and completion; return a response for the middle operation; assert only that operation is removed, later operations remain, and the canonical task is stored.

- [ ] **Step 4: Implement keyed sync and blocked states.**

Serialize by `taskId`, mark one operation `in_flight`, confirm the matching `operationId`, rebase remaining operations onto the returned task, mark schedule/deleted conflicts as `blocked`, and retain transient failures as `pending` with backoff.

- [ ] **Step 5: Wire worker lifecycle to the authenticated runtime.**

Wake on connectivity, foreground safety interval and local task mutation. Run the task worker before feed drain so local writes reach the server before remote snapshots are applied.

- [ ] **Step 6: Run focused tests and commit.**

Run: `flutter test test/features/tasks/data test/core/sync/standalone_task_outbox_worker_test.dart`

Expected: PASS for network retry, exact confirmation, ordering and blocked protocol errors.

```powershell
git add lib/features/tasks/data lib/core/sync lib/core/di test/features/tasks/data test/core/sync
git commit -m "feat(tasks): sync standalone task outbox"
```

### Task 7: Criar leitura de tasks de notas, agregação e histórico

**Files:**
- Create: `lib/features/tasks/domain/note_task_list_reader.dart`
- Create: `lib/features/tasks/application/task_list_providers.dart`
- Modify: `lib/features/tasks/domain/note_task_reader.dart` only for shared pure parsing helpers
- Test: `test/features/tasks/domain/note_task_list_reader_test.dart`
- Test: `test/features/tasks/application/task_list_providers_test.dart`

**Interfaces:**
- `NoteTaskListReader.read({required String noteId, required String noteTitle, required String documentJson, required bool hideCompleted}) -> List<TaskListItem>`.
- `taskListProvider({required bool includeNoteTasks}) -> StreamProvider<List<TaskListItem>>`.
- `completedTaskHistoryProvider({required bool includeNoteTasks}) -> StreamProvider<List<TaskHistoryEntry>>`.
- `taskNotesVisibilityProvider -> StreamProvider<List<VisibleNoteDocument>>`.

- [ ] **Step 1: Write reader tests separate from notification semantics.**

Assert that an overdue recurring task remains represented by its visible occurrence, an undated task remains in the list, completed items are excluded from the open stream, and `noteId`/`blockId` are preserved.

Run: `flutter test test/features/tasks/domain/note_task_list_reader_test.dart`

Expected: FAIL because the list reader does not exist.

- [ ] **Step 2: Implement the list reader without `TaskNotificationEntry`.**

Reuse `NoteDocumentCodec`, metadata parsing and `TaskOccurrencePolicy`, but return `TaskListItem` without requiring a reminder and never choose a future occurrence merely for notification scheduling.

- [ ] **Step 3: Implement visible-note selection.**

Read effective documents, filter deleted/revoked/inaccessible notes, honor `hide_completed`, and attach note titles from the catalog. Surface extraction errors as provider errors instead of silently dropping a note.

- [ ] **Step 4: Implement merge, ordering and temporal invalidation.**

Merge standalone stream with optional note stream, sort overdue/today/future/undated, use an injectable `TaskListClock`, and schedule invalidation at the next date/time boundary. Use composite UI key `source + taskId + noteId + blockId`.

- [ ] **Step 5: Implement history projection.**

Project `lastCompletedAt` for non-recurring tasks and one entry per `completions` key for recurring tasks; sort by `completedAt DESC`; include note tasks only when the same filter is enabled.

- [ ] **Step 6: Run focused result tests and commit.**

Run: `flutter test test/features/tasks/domain/note_task_list_reader_test.dart test/features/tasks/application/task_list_providers_test.dart`

Expected: PASS for aggregation, filtering, time boundary, ordering and history.

```powershell
git add lib/features/tasks/domain lib/features/tasks/application test/features/tasks/domain test/features/tasks/application
git commit -m "feat(tasks): aggregate standalone and note task lists"
```

### Task 8: Unificar notificações das duas fontes

**Files:**
- Create: `lib/features/tasks/domain/standalone_task_notification_source.dart`
- Modify: `lib/features/tasks/domain/task_notification_id.dart`
- Modify: `lib/features/tasks/domain/task_notification_scheduler.dart`
- Modify: `lib/features/tasks/domain/note_task_notification_source.dart`
- Test: `test/features/tasks/domain/standalone_task_notification_source_test.dart`
- Test: `test/features/tasks/domain/task_notification_id_test.dart`

**Interfaces:**
- `StandaloneTaskNotificationSource.readOpenTasks(String userId) -> Future<List<TaskNotificationEntry>>`.
- `TaskNotificationId.forStandalone({required String userId, required String taskId, required DateTime scheduledAt})`.
- `TaskNotificationId.forNote({required String userId, required String noteId, required String blockId, required DateTime scheduledAt})`.

- [ ] **Step 1: Write collision and rescheduling tests.**

Use equal task IDs in two sources and assert different notification IDs. Assert that an ID format change cancels the persisted legacy ID before scheduling the new one.

- [ ] **Step 2: Implement standalone reader with the shared occurrence policy.**

Read open local tasks, resolve the current notification occurrence, skip completed/tombstoned tasks, and return `TaskNotificationEntry` without importing UI models.

- [ ] **Step 3: Update scheduler identity and union source.**

Include user ID and full source identity in the notification ID, reconcile standalone and note entries together, and keep the list filter independent from reminder scheduling.

- [ ] **Step 4: Run focused notification tests and commit.**

Run: `flutter test test/features/tasks/domain/standalone_task_notification_source_test.dart test/features/tasks/domain/task_notification_id_test.dart test/features/tasks/domain/note_task_reader_test.dart`

Expected: PASS with no layout tests.

```powershell
git add lib/features/tasks/domain test/features/tasks/domain
git commit -m "feat(tasks): schedule reminders for both task sources"
```

### Task 9: Adicionar shell de navegação e rotas Tasks/Notas

**Files:**
- Create: `lib/shared/widgets/app_navigation_shell.dart`
- Modify: `lib/core/router/app_routes.dart`
- Modify: `lib/core/router/app_router.dart`
- Modify: `lib/features/notes/editor/presentation/note_editor_screen.dart`
- Test: `test/core/router/app_router_test.dart`

**Interfaces:**
- `AppNavigationShell` accepts `StatefulNavigationShell` and exposes `Tasks` and `Notas`.
- `AppRoutes.tasks`, `AppRoutes.notes`, `AppRoutes.completedTasks`, `AppRoutes.standaloneTask` and `AppRoutes.note(String id, {String? blockId})` are the route builders used by the feature.

- [ ] **Step 1: Write route behavior tests.**

Assert that authenticated `/home` redirects to Tasks, the two destinations preserve branch state, `/tasks/completed` is reachable, and `/notes/:id?blockId=...` preserves the block ID.

Run: `flutter test test/core/router/app_router_test.dart`

Expected: FAIL because shell routes do not exist.

- [ ] **Step 2: Implement `StatefulShellRoute.indexedStack`.**

Keep settings, MCP, auth and Share Link routes outside the shell. Place Tasks in branch index 0 and the existing notes catalog/editor flow in branch index 1.

- [ ] **Step 3: Implement the shared public navigation component.**

Use `NavigationBar` with two destinations and existing theme tokens. Do not add a visual snapshot test.

- [ ] **Step 4: Pass `blockId` into `NoteEditorScreen`.**

Use the editor session/document lookup to focus the matching task block; if absent, open the note normally and expose the missing target as recoverable navigation state.

- [ ] **Step 5: Run route tests and commit.**

Run: `flutter test test/core/router/app_router_test.dart test/features/notes/presentation/note_editor_screen_test.dart`

Expected: PASS for navigation and block targeting.

```powershell
git add lib/shared/widgets lib/core/router lib/features/notes/editor/presentation test/core/router test/features/notes/presentation
git commit -m "feat(navigation): add tasks and notes tabs"
```

### Task 10: Implementar tela Tasks, histórico e editor independente

**Files:**
- Create: `lib/features/tasks/presentation/tasks_screen.dart`
- Create: `lib/features/tasks/presentation/completed_tasks_screen.dart`
- Create: `lib/features/tasks/presentation/standalone_task_editor_screen.dart`
- Create: `lib/features/tasks/presentation/widgets/task_list_tile.dart`
- Create: `lib/features/tasks/presentation/widgets/task_source_label.dart`
- Create: `lib/features/tasks/presentation/widgets/completed_tasks_tile.dart`
- Create: `lib/features/tasks/presentation/widgets/standalone_task_form.dart`
- Create: `lib/features/tasks/application/standalone_task_controller.dart`
- Modify: `lib/core/router/app_router.dart`
- Test: `test/features/tasks/presentation/tasks_screen_test.dart`
- Test: `test/features/tasks/presentation/completed_tasks_screen_test.dart`
- Test: `test/features/tasks/application/standalone_task_controller_test.dart`

**Interfaces:**
- `TasksScreen` reads `taskListProvider(includeNoteTasks: ...)` and uses `AsyncValue.when`.
- `StandaloneTaskController.create/update/complete/reopen/delete` delegates to `StandaloneTaskRepository` and returns `Future<void>`.
- `TaskListTile` receives `TaskListItem` and callbacks; it never reads a repository directly.

- [ ] **Step 1: Write behavioral tests.**

Test that the screen exposes the completed destination, toggling the note-task preference changes the provider input, tapping a standalone item navigates to its editor, tapping a note item navigates with `noteId`/`blockId`, and the controller delegates completion to the correct repository operation.

Run: `flutter test test/features/tasks/presentation/tasks_screen_test.dart test/features/tasks/presentation/completed_tasks_screen_test.dart test/features/tasks/application/standalone_task_controller_test.dart`

Expected: FAIL because screens, controller and routes do not exist.

- [ ] **Step 2: Implement the standalone editor with shared inputs and metadata sheet.**

Use `TextEditingController`, `AppInput`, `AppButton`, `showAppBottomSheet` and existing task metadata components. Keep the screen in edit mode only; save through the controller and expose failures through the provider/error UI.

- [ ] **Step 3: Implement `TasksScreen` with required slivers.**

Use `Scaffold`, `CustomScrollView`, `SliverAppBar.medium`, `SliverPadding`, `SliverList` and `AppButton` for add. Add the note-task toggle, list tiles, loading/error/empty states and final **Concluídas** tile.

- [ ] **Step 4: Implement history and source navigation.**

Render `TaskHistoryEntry` descending by completion. A note entry pushes the note route with `blockId`; a standalone entry pushes its editor.

- [ ] **Step 5: Run focused behavioral tests and commit.**

Run: `flutter test test/features/tasks/presentation test/features/tasks/application/standalone_task_controller_test.dart`

Expected: PASS without size, color, pixel-position or geometry assertions.

```powershell
git add lib/features/tasks/presentation lib/features/tasks/application lib/core/router test/features/tasks/presentation test/features/tasks/application
git commit -m "feat(tasks): add task list and completion history"
```

### Task 11: Atualizar documentação, invariantes e operação de migração

**Files:**
- Modify: `AGENTS.md`
- Modify: `CONTEXT.md`
- Modify: `lib/features/tasks/README.md`
- Modify: `docs/architecture/backend-file-reference.md`
- Modify: `docs/operations/task-document-migration-runbook.md`
- Modify: `implementation_plan.md`

**Interfaces:**
- Documentation states that document tasks use `TaskNode`, independent tasks use `tasks`, and neither table is a projection of the other.
- The runbook documents PostgreSQL backup, retention gate, SQLite quarantine, rollback guard and old-client feed compatibility.

- [ ] **Step 1: Search for contradictory projection claims.**

Run: `rg -n -i "TaskProjectionEngine|tasks table|relational task|direct.*tasks|task_completions" AGENTS.md CONTEXT.md lib/features/tasks docs/architecture docs/operations`.

Expected: each remaining statement identifies whether it is historical, migration evidence or the new independent-task resource.

- [ ] **Step 2: Update normative docs and runbook.**

Remove the stale claim that every `tasks` row is a document projection; preserve historical SQL scripts as non-runtime evidence; document that PostgreSQL legacy rows are never auto-converted and SQLite remnants are quarantined.

- [ ] **Step 3: Run documentation searches and commit.**

Run: `git diff --check`; repeat the `rg` command and verify no contradictory normative statement remains.

```powershell
git add AGENTS.md CONTEXT.md lib/features/tasks/README.md docs/architecture docs/operations implementation_plan.md
git commit -m "docs(tasks): align task ownership and migration rules"
```

### Task 12: Verificação integrada e rollout seguro

**Files:**
- Create: `docs/superpowers/walkthroughs/2026-09-15-standalone-tasks-tabs.md`
- Modify: `task.md`
- Test: existing focused suites and backend suite

**Interfaces:**
- Produces a walkthrough with command output, migration gates, known limitations and rollback procedure.
- Produces a checked task list with every implementation step marked only after evidence exists.

- [ ] **Step 1: Run focused Flutter domain/data/sync tests.**

Run: `flutter test test/features/tasks/domain test/features/tasks/data test/features/tasks/application test/core/sync test/core/database/daos/standalone_tasks_dao_test.dart`.

Expected: PASS with no visual-only tests added.

- [ ] **Step 2: Run focused navigation and task behavior tests.**

Run: `flutter test test/core/router/app_router_test.dart test/features/tasks/presentation`.

Expected: PASS for route targets, filtering, history and controller outcomes.

- [ ] **Step 3: Run analyzer and backend validation.**

Run: `flutter analyze`; `go test ./...`; `go vet ./...`; `git diff --check`.

Expected: analyzer clean, Go tests and vet pass, and no whitespace errors. A timeout or no-output command is recorded as inconclusive, not success.

- [ ] **Step 4: Exercise migration in an isolated database.**

Run `make -C backend dev-db-up`, apply migrations with `make -C backend migrate-up`, verify quarantine names/counts, run migration integration tests, and perform a restore rehearsal before production approval. Do not run destructive cleanup against production from the development shell.

- [ ] **Step 5: Write walkthrough and commit only verified evidence.**

```powershell
git add docs/superpowers/walkthroughs/2026-09-15-standalone-tasks-tabs.md task.md
git commit -m "docs(tasks): record standalone task rollout verification"
```

## Self-review checklist

- [ ] Every spec section has at least one implementation task.
- [ ] Feed compatibility, task bootstrap, operation confirmation and schedule-generation conflicts are covered by code and tests.
- [ ] PostgreSQL legacy tables are quarantined only with the retention gate; SQLite remnants are never deleted implicitly.
- [ ] The list uses a dedicated note-task reader and does not reuse notification DTOs.
- [ ] Note visibility, notification identity and temporal invalidation are explicitly tested.
- [ ] No step uses placeholder markers, an undefined function, or a visual-only assertion.
- [ ] Generated sqlc/Drift files are regenerated by their documented commands instead of edited manually.

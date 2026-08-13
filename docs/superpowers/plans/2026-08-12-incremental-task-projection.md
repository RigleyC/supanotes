# Projeção incremental de tarefas Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Reduzir a leitura e a escrita da projeção local de tarefas para mudanças pequenas, preservando o snapshot REST/OT como fonte canônica e provando igualdade com o rebuild completo.

**Architecture:** Criar um ProjectionChangeSet puro em core/sync para representar IDs alterados, IDs removidos, faixa estrutural, revisão e necessidade de rebuild. O editor e o adapter produzem esse conjunto para operações locais, remotas e rebased; o TaskProjectionEngine calcula content/excerpt completamente, mas calcula tarefas somente para os IDs afetados. Hydration, recovery, repair, operação desconhecida e inconsistência continuam usando o caminho completo atual.

**Tech Stack:** Flutter 3.44.1, Dart 3.10, SuperEditor, Drift/SQLite, flutter_test, integration_test, GitHub Actions.

## Global Constraints

- notes.document/REST-OT remains the single source of truth for note content and task metadata.
- Task content and metadata changes flow through NoteSyncSession / EditorOperationCapture / NoteOperationAdapter.
- Do not edit generated Drift files.
- Do not alter the REST/OT wire contract.
- Do not add backward-compatibility paths, migrations, or a durable block index.
- Keep content and excerpt on the full calculation path in this phase.
- Persist note content and task projection atomically in one database transaction.
- Unknown or unclassifiable impact must request an explicit full rebuild.
- Run Flutter checks sequentially; concurrent Flutter processes are not allowed.
- Preserve unrelated work already present in the workspace.
- Keep new methods below the GitHub cognitive-complexity threshold of 15.
- Do not claim CI success until the relevant GitHub Actions run is green.

---

## Task 0: Establish a clean, reproducible baseline

Files:

- Read only: .github/workflows/android.yml
- Read only: .github/workflows/complexity.yml
- Read only: .github/workflows/backend.yml
- Read only: integration_test/full_suite_test.dart
- Read only: test/README.md

Interfaces:

- Consumes: current branch and current workspace state.
- Produces: a recorded baseline; no source change.

- [ ] Step 1: Confirm branch and unrelated changes

    rtk git status --short
    rtk git branch --show-current
    rtk git log -1 --oneline

Expected: the implementation starts from the current non-main branch. Record any
pre-existing change and exclude it from staging.

- [ ] Step 2: Run the analyzer baseline

    rtk flutter analyze --no-fatal-infos

Expected: exit code 0. If it fails before implementation, record the exact
failure and stop instead of attributing it to this feature.

- [ ] Step 3: Run the Flutter baseline

    rtk flutter test

Expected: exit code 0, with the existing skip count recorded separately.

- [ ] Step 4: Run the existing Windows integration baseline

    rtk flutter test integration_test/full_suite_test.dart -d windows

Expected: all existing integration tests pass. If Windows is unavailable, record
the environment blocker; do not replace this check with a unit test and call it
E2E coverage.

- [ ] Step 5: Keep baseline evidence separate

Record command, exit code, test count, skip count, and known warnings in the
implementation handoff. Do not overwrite the historical implementation_plan.md
or walkthrough.md during this step.

---

## Task 1: Add the pure ProjectionChangeSet contract

Files:

- Create: lib/core/sync/projection_change_set.dart
- Create: test/core/sync/projection_change_set_test.dart

Interfaces:

- Consumes: neutral operation descriptors and previous/final block ID order.
- Produces: ProjectionOperation, ProjectionChangeSet, merge, and affectedBlockIds.

- [ ] Step 1: Write failing tests for direct operations

    test('text and metadata operations affect only their block', () {
      final result = ProjectionChangeSet.fromOperations(
        operations: [
          const ProjectionOperation(
            operationId: 'op-text',
            kind: 'text_delta',
            blockId: 'task-2',
            payload: {'ops': []},
          ),
          const ProjectionOperation(
            operationId: 'op-meta',
            kind: 'set_block_metadata',
            blockId: 'task-4',
            payload: {'metadata': {}},
          ),
        ],
        previousOrder: ['task-1', 'task-2', 'task-3', 'task-4'],
        currentOrder: ['task-1', 'task-2', 'task-3', 'task-4'],
        canonicalRevision: 7,
      );

      expect(result.changedBlockIds, {'task-2', 'task-4'});
      expect(result.deletedBlockIds, isEmpty);
      expect(result.hasStructuralChange, isFalse);
      expect(result.requiresFullRebuild, isFalse);
      expect(result.firstAffectedIndex, isNull);
      expect(result.canonicalRevision, 7);
    });

Also test create, delete, move, unknown kind, missing ID, structural index
calculation, merge, and deleted IDs taking precedence over changed IDs.

- [ ] Step 2: Run the focused test and verify RED

    rtk flutter test test/core/sync/projection_change_set_test.dart

Expected: FAIL because the classifier does not exist. Fix setup errors until
the failure is caused by the missing behavior.

- [ ] Step 3: Implement the smallest pure classifier

Use these public members:

    class ProjectionOperation {
      const ProjectionOperation({
        required this.operationId,
        required this.kind,
        required this.blockId,
        required this.payload,
      });

      final String operationId;
      final String kind;
      final String? blockId;
      final Map<String, dynamic> payload;
    }

    class ProjectionChangeSet {
      const ProjectionChangeSet({
        required this.changedBlockIds,
        required this.deletedBlockIds,
        required this.firstAffectedIndex,
        required this.hasStructuralChange,
        required this.requiresFullRebuild,
        required this.canonicalRevision,
        required this.operationIds,
        this.fullRebuildReason,
      });

      final Set<String> changedBlockIds;
      final Set<String> deletedBlockIds;
      final int? firstAffectedIndex;
      final bool hasStructuralChange;
      final bool requiresFullRebuild;
      final int? canonicalRevision;
      final Set<String> operationIds;
      final String? fullRebuildReason;

      Set<String> affectedBlockIds(List<String> finalOrder);
      ProjectionChangeSet merge(ProjectionChangeSet other);

      static ProjectionChangeSet fromOperations({
        required Iterable<ProjectionOperation> operations,
        required List<String> previousOrder,
        required List<String> currentOrder,
        int? canonicalRevision,
      });

      static ProjectionChangeSet empty({int? canonicalRevision});
      static ProjectionChangeSet fullRebuild({
        required String reason,
        int? canonicalRevision,
        Iterable<String> operationIds = const [],
      });
    }

Use only the seven existing wire names. Require a block ID for every operation
except a valid create payload that supplies id. Unknown kinds, malformed
payloads, and missing structural positions produce an explicit full rebuild.
affectedBlockIds includes final IDs from firstAffectedIndex through the end and
includes deleted IDs. merge unions IDs, keeps the smallest structural index,
keeps the newest non-null revision, and lets full rebuild dominate.

- [ ] Step 4: Run focused tests and formatter

    rtk dart format lib/core/sync/projection_change_set.dart test/core/sync/projection_change_set_test.dart
    rtk flutter test test/core/sync/projection_change_set_test.dart

Expected: all tests pass and the classifier has no database or editor dependency.

- [ ] Step 5: Commit the pure contract

    rtk git add lib/core/sync/projection_change_set.dart test/core/sync/projection_change_set_test.dart
    rtk git commit -m "feat(sync): classify incremental projection changes"

---

## Task 2: Emit impact from local editor capture and the adapter

Files:

- Modify: lib/features/notes/editor/sync/editor_operation_capture.dart
- Modify: lib/features/notes/editor/sync/note_operation_adapter.dart
- Modify: test/features/notes/domain/editor_operation_capture_test.dart
- Modify: test/features/notes/domain/note_operation_adapter_test.dart

Interfaces:

- Consumes: ProjectionChangeSet.fromOperations and the existing editor mirror.
- Produces: CapturedOperationBatch, LocalOperationBatch, and an adapter
  callback carrying operations plus projection impact.

- [ ] Step 1: Write failing tests for local capture

Use the real editor setup and assert that a text edit has only the target ID,
while delete and move have structural impact:

    test('captures a text edit without structural projection impact', () {
      final batches = <CapturedOperationBatch>[];
      final capture = EditorOperationCapture(
        document: document,
        generateOpId: () => 'op-1',
        codec: const NoteDocumentCodec(),
        onOperationsCaptured: batches.add,
      );

      capture.start();
      editor.execute([
        InsertTextRequest(
          documentPosition: const DocumentPosition(
            nodeId: 'task-2',
            nodePosition: TextNodePosition(offset: 0),
          ),
          textToInsert: 'x',
          attributions: {},
        ),
      ]);

      expect(batches.single.changeSet.changedBlockIds, {'task-2'});
      expect(batches.single.changeSet.hasStructuralChange, isFalse);
    });

- [ ] Step 2: Run capture tests and verify RED

    rtk flutter test test/features/notes/domain/editor_operation_capture_test.dart

Expected: FAIL because the callback returns only a list.

- [ ] Step 3: Add explicit batch types

Add small value types at this boundary:

    class CapturedOperationBatch {
      const CapturedOperationBatch({
        required this.operations,
        required this.changeSet,
      });

      final List<OperationRequestData> operations;
      final ProjectionChangeSet changeSet;
    }

    class LocalOperationBatch {
      const LocalOperationBatch({
        required this.operations,
        required this.changeSet,
      });

      final List<OperationRequest> operations;
      final ProjectionChangeSet changeSet;

      static LocalOperationBatch get empty => LocalOperationBatch(
        operations: const <OperationRequest>[],
        changeSet: ProjectionChangeSet.empty(),
      );
    }

Change the capture callback to emit the batch. Build the change set before
replacing _orderedNodeIds with the current order. Keep operation generation,
composition deferral, and mirror updates unchanged.

In NoteOperationAdapter, merge captured sets while _pendingOps is coalesced.
Call onLocalOperations(LocalOperationBatch(...)) only after the outbox write
succeeds. If it fails, restore both operations and the set.

- [ ] Step 4: Preserve operation-level adapter assertions

Update existing callbacks from ops to batch.operations. Add:

    test('publishes projection impact only after outbox persistence', () async {
      final adapter = createAdapter();
      LocalOperationBatch? batch;
      adapter.onLocalOperations = (value) => batch = value;

      await adapter.start();
      editor.execute([
        InsertTextRequest(
          documentPosition: const DocumentPosition(
            nodeId: 'block-1',
            nodePosition: TextNodePosition(offset: 0),
          ),
          textToInsert: '!',
          attributions: {},
        ),
      ]);
      await adapter.flushNow();

      expect(batch, isNotNull);
      expect(batch!.operations, hasLength(1));
      expect(batch!.changeSet.changedBlockIds, {'block-1'});
    });

Use real capture and outbox code; do not mock the behavior under test.

- [ ] Step 5: Run focused capture and adapter tests

    rtk flutter test test/features/notes/domain/editor_operation_capture_test.dart test/features/notes/domain/note_operation_adapter_test.dart

Expected: existing operation tests and new change-set tests pass.

- [ ] Step 6: Commit the local capture seam

    rtk git add lib/features/notes/editor/sync/editor_operation_capture.dart lib/features/notes/editor/sync/note_operation_adapter.dart test/features/notes/domain/editor_operation_capture_test.dart test/features/notes/domain/note_operation_adapter_test.dart
    rtk git commit -m "feat(notes): attach projection impact to local operations"

---

## Task 3: Select affected tasks in the pure projector

Files:

- Modify: lib/features/tasks/domain/projected_document.dart
- Modify: lib/features/tasks/domain/note_document_projector.dart
- Modify: lib/features/tasks/domain/task_projection_engine.dart
- Modify: test/features/tasks/domain/note_document_projector_test.dart
- Modify: test/features/tasks/domain/task_projection_engine_test.dart

Interfaces:

- Consumes: final blocks and optional ProjectionChangeSet.
- Produces: ProjectedDocument.affectedBlockIds and selected tasks, while the
  full API remains unchanged when no set is provided.

- [ ] Step 1: Write failing projector tests

Create a fixture with tasks at indexes 0, 2, and 4. A text change set for task 2
must return only task 2, while content and excerpt still contain every block.
A structural set must select every final ID from its first affected index and
include deleted IDs in affectedBlockIds.

- [ ] Step 2: Run tests and verify RED

    rtk flutter test test/features/tasks/domain/note_document_projector_test.dart

Expected: FAIL because the projector has no change-set parameter or affected ID
result.

- [ ] Step 3: Extend the result without changing full semantics

Add final Set<String> affectedBlockIds to ProjectedDocument. Extend projectBlocks
with ProjectionChangeSet? changeSet.

Always append every block's plain text to the content buffer. Only create a
ProjectedTask when the block is selected or the path is full. Reuse the current
recurrence, due date, completion, reminder, and excerpt code unchanged.

- [ ] Step 4: Add the optional engine API

Use:

    Future<void> projectTasksFromSnapshot({
      required String noteId,
      required Map<String, dynamic> snapshot,
      String userId = '',
      ProjectionChangeSet? changeSet,
    });

    Future<void> projectTasksFromDocument({
      required String noteId,
      required MutableDocument document,
      String userId = '',
      ProjectionChangeSet? changeSet,
    });

Null or full-rebuild sets use saveProjectedDocument. Incremental sets use
saveIncrementalProjectedDocument with selected tasks and affected IDs.

- [ ] Step 5: Run task projection tests

    rtk flutter test test/features/tasks/domain/note_document_projector_test.dart test/features/tasks/domain/task_projection_engine_test.dart

Expected: existing recurrence, atomicity, empty-note, and remote aggregate tests
remain green, plus the new selected-task tests.

- [ ] Step 6: Commit the pure selection path

    rtk git add lib/features/tasks/domain/projected_document.dart lib/features/tasks/domain/note_document_projector.dart lib/features/tasks/domain/task_projection_engine.dart test/features/tasks/domain/note_document_projector_test.dart test/features/tasks/domain/task_projection_engine_test.dart
    rtk git commit -m "feat(tasks): select affected blocks for projection"

---

## Task 4: Apply incremental task rows atomically in Drift

Files:

- Modify: lib/core/database/daos/tasks_dao.dart
- Modify: lib/core/database/database.dart
- Modify: test/core/database/daos/tasks_dao_test.dart
- Modify: test/features/tasks/domain/task_projection_engine_test.dart

Interfaces:

- Consumes: affected IDs and selected ProjectedTask values.
- Produces: TasksDao.applyProjectedTaskChanges and
  AppDatabase.saveIncrementalProjectedDocument.

- [ ] Step 1: Write failing DAO tests

Create three active tasks, apply a change set for only the middle task, and assert
that the middle title changes while the first and last updatedAt, title, status,
and deletedAt remain unchanged. Add tests for task-to-paragraph, new task,
deleted task, and structural suffix positions.

- [ ] Step 2: Run DAO tests and verify RED

    rtk flutter test test/core/database/daos/tasks_dao_test.dart

Expected: FAIL because the incremental database method does not exist.

- [ ] Step 3: Implement the DAO operation without a nested transaction

Define the returned value as:

    class ProjectedTaskWriteStats {
      const ProjectedTaskWriteStats({
        required this.rowsRead,
        required this.rowsUpserted,
        required this.rowsDeleted,
      });

      final int rowsRead;
      final int rowsUpserted;
      final int rowsDeleted;
    }

Add:

    Future<ProjectedTaskWriteStats> applyProjectedTaskChanges(
      String noteId,
      Set<String> affectedBlockIds,
      List<ProjectedTask> projectedTasks, {
      String userId = '',
    }) async;

Query active rows by note and affected IDs only. Skip the task query when the
set is empty. Mark an affected existing row deleted when it is absent from the
incoming list. Upsert incoming rows using the same user ID, created time,
completion time, recurrence, and reminder rules as the full path. Return
rowsRead, rowsUpserted, and rowsDeleted.

- [ ] Step 4: Add the aggregate transaction

Add:

    Future<ProjectedTaskWriteStats> saveIncrementalProjectedDocument({
      required String noteId,
      required String content,
      String? excerpt,
      required Set<String> affectedBlockIds,
      required List<ProjectedTask> tasks,
      String userId = '',
    });

Open the transaction in AppDatabase, update the note projection, call the DAO
operation, and return its stats. Do not edit database.g.dart. Extract a small
private upsert helper if needed so full and incremental paths cannot diverge in
recurrence or completion behavior.

- [ ] Step 5: Add atomic rollback coverage

Extend the failing database setup with an incremental failure. After the
exception, note content, excerpt, original task, and unrelated task must retain
their previous values.

- [ ] Step 6: Run focused persistence tests

    rtk flutter test test/core/database/daos/tasks_dao_test.dart test/features/tasks/domain/task_projection_engine_test.dart

Expected: full-path and incremental row/rollback tests pass.

- [ ] Step 7: Commit atomic persistence

    rtk git add lib/core/database/daos/tasks_dao.dart lib/core/database/database.dart test/core/database/daos/tasks_dao_test.dart test/features/tasks/domain/task_projection_engine_test.dart
    rtk git commit -m "feat(database): persist affected task rows atomically"

---

## Task 5: Connect local, remote, rebased, and coalesced session work

Files:

- Modify: lib/features/notes/editor/sync/note_operation_adapter.dart
- Modify: lib/features/notes/editor/sync/note_sync_session.dart
- Modify: test/features/notes/domain/note_operation_adapter_test.dart
- Modify: test/features/notes/domain/note_sync_session_test.dart
- Modify: test/features/notes/domain/sync_characterization_test.dart

Interfaces:

- Consumes: LocalOperationBatch, ProjectionChangeSet, and the optional engine
  change-set parameter.
- Produces: one serialized projection queue for local, remote, and rebased
  changes with explicit full rebuilds.

- [ ] Step 1: Write failing adapter tests for remote classification

Change reconcile to be tested as:

    final changeSet = await adapter.reconcile(result);

    expect(changeSet, isNotNull);
    expect(changeSet!.changedBlockIds, contains('remote-task'));
    expect(changeSet.canonicalRevision, 12);

Cover remote text, remote move, remote delete, a remote batch with rebased
pending operations, and a canonical snapshot without classifiable operations.
The last case must require a full rebuild. Preserve editor selection and
composition behavior.

- [ ] Step 2: Run tests and verify RED

    rtk flutter test test/features/notes/domain/note_operation_adapter_test.dart test/features/notes/domain/note_sync_session_test.dart test/features/notes/domain/sync_characterization_test.dart

Expected: compile or assertion failures because reconcile returns void and the
session schedules a full projection for every callback.

- [ ] Step 3: Return one remote/rebased set from reconcile

Use:

    Future<ProjectionChangeSet?> reconcile(SyncResult result);

Capture block order before and after applying the canonical snapshot and rebased
operations. Convert Operation and PendingNoteOperationData to neutral
ProjectionOperation values and classify them with the final revision.

Preserve the local-ack rule: a response that confirms already projected local
work returns null. A canonical snapshot with no operations that explain its
change returns an explicit full-rebuild set. Do not write remote operations
directly to tasks.

- [ ] Step 4: Make the session queue accept and coalesce sets

Use:

    void _handleLocalOperations(LocalOperationBatch batch);
    Future<void> _enqueueProjection(ProjectionChangeSet changeSet);
    Future<void> _projectDocument(ProjectionChangeSet? changeSet);

Keep startup as an explicit full rebuild. For local work, enqueue batch.changeSet
and start sync. For remote work, enqueue only the set returned by reconcile; do
not enqueue a second full projection for a local acknowledgement.

Coalesce pending work by unioning changed IDs, unioning deleted IDs with delete
precedence, keeping the smallest structural index, letting full rebuild dominate,
and keeping the newest revision and document state. Keep projection transactions
serialized. A change during a database await enters the next queue item.

- [ ] Step 5: Update characterization fakes

Update RecordingTaskProjectionEngine, GateTaskProjectionEngine,
BlockingTaskProjectionEngine, and FailingTaskProjectionEngine to accept
ProjectionChangeSet? changeSet. Replace direct empty callback calls with
LocalOperationBatch.empty. Keep status, error, and non-overlap assertions.

- [ ] Step 6: Add session regression tests

Add one test that starts a real session, publishes one local batch, returns an
ack-only SyncResult, waits for the projection queue, and asserts one projection
call. Add a second test that blocks the first projection, publishes two local
batches, releases the first call, and asserts maxConcurrent equals 1 and the
second call receives the merged set. Use real session setup and mock only the
HTTP sync boundary.

- [ ] Step 7: Run session and sync tests

    rtk flutter test test/features/notes/domain/note_operation_adapter_test.dart test/features/notes/domain/note_sync_session_test.dart test/features/notes/domain/sync_characterization_test.dart

Expected: local outbox, remote rebase, selection, status, and serialized
projection tests pass.

- [ ] Step 8: Commit session integration

    rtk git add lib/features/notes/editor/sync/note_operation_adapter.dart lib/features/notes/editor/sync/note_sync_session.dart test/features/notes/domain/note_operation_adapter_test.dart test/features/notes/domain/note_sync_session_test.dart test/features/notes/domain/sync_characterization_test.dart
    rtk git commit -m "feat(sync): drive task projection from change sets"

---

## Task 6: Add telemetry and a correctness-first benchmark

Files:

- Modify: lib/features/tasks/domain/task_projection_engine.dart
- Modify: lib/core/database/database.dart
- Modify: lib/core/database/daos/tasks_dao.dart
- Create: test/features/tasks/domain/task_projection_benchmark_test.dart
- Modify: test/features/tasks/domain/task_projection_engine_test.dart

Interfaces:

- Consumes: ProjectedTaskWriteStats.
- Produces: non-private projection telemetry and a 1/100/1,000-block comparison.

- [ ] Step 1: Write benchmark assertions

Create deterministic fixtures with tasks at beginning, middle, and end. For
each size, compare full and incremental results field by field for every task,
content, and excerpt. Print elapsed time and row stats. Assert equality, not a
timing threshold.

- [ ] Step 2: Run the benchmark and verify RED

    rtk flutter test test/features/tasks/domain/task_projection_benchmark_test.dart

Expected: FAIL until incremental projection and row stats exist.

- [ ] Step 3: Emit only safe telemetry

Use NoteSyncDebug.log with:

    projectionMode
    operationCount
    changedBlockCount
    affectedBlockCount
    projectedTaskCount
    rowsRead
    rowsUpserted
    rowsDeleted
    canonicalRevision
    fullRebuildReason

Never log document text, Delta payloads, task titles, or user content. Keep this
in one small method.

- [ ] Step 4: Run benchmark and projection tests

    rtk dart format test/features/tasks/domain/task_projection_benchmark_test.dart lib/features/tasks/domain/task_projection_engine.dart lib/core/database/daos/tasks_dao.dart lib/core/database/database.dart
    rtk flutter test test/features/tasks/domain/task_projection_benchmark_test.dart test/features/tasks/domain/task_projection_engine_test.dart

Expected: equality passes for all sizes and output reports actual affected rows.

- [ ] Step 5: Commit telemetry and benchmark

    rtk git add lib/features/tasks/domain/task_projection_engine.dart lib/core/database/database.dart lib/core/database/daos/tasks_dao.dart test/features/tasks/domain/task_projection_benchmark_test.dart test/features/tasks/domain/task_projection_engine_test.dart
    rtk git commit -m "test(tasks): benchmark incremental projection correctness"

---

## Task 7: Add the end-to-end regression path

Files:

- Modify: integration_test/full_suite_test.dart
- Modify: docs/e2e-test-scenario-matrix.md

Interfaces:

- Consumes: real app database, editor, adapter/session, engine, and Drift.
- Produces: an offline local-edit E2E regression.

- [ ] Step 1: Add the E2E oracle after the focused red-green cycles

Create a note with three task blocks, open a real NoteSyncSession with the
offline client, edit only the middle task through an editor request, flush, wait
for the projection queue, and read the database. Assert the edited task changed,
unrelated tasks remain active and unchanged, and notes.content/notes.excerpt
contain all blocks.

- [ ] Step 2: Run the E2E oracle

    rtk flutter test integration_test/full_suite_test.dart -d windows

The production seams were already driven by failing unit/integration tests in
Tasks 1 through 5. This task adds the end-to-end oracle and is expected to pass
when those focused cycles are green; a first-run pass here is not used as proof
that a production change was made without a preceding failing test.

- [ ] Step 3: Implement only the production-path fixture

Reuse _OfflineClient, existing document/editor setup, and teardown patterns. Do
not add a test-only projection path or a second sync protocol.

- [ ] Step 4: Run E2E again

    rtk flutter test integration_test/full_suite_test.dart -d windows

Expected: all integration tests pass. If Windows is unavailable, report the
exact limitation and do not report E2E as passed.

- [ ] Step 5: Commit E2E coverage

    rtk git add integration_test/full_suite_test.dart docs/e2e-test-scenario-matrix.md
    rtk git commit -m "test(notes): cover offline incremental task projection"

---

## Task 8: Full regression, review, and CI verification

Files:

- Read only: all changed files and .github/workflows/*.yml
- Modify: task.md with completed checklist
- Modify: walkthrough.md with final evidence

Interfaces:

- Consumes: all implementation commits and focused tests.
- Produces: verified branch state and a truthful handoff that separates local,
  E2E, and GitHub CI results.

- [ ] Step 1: Run formatting and diff checks

    rtk dart format --output=none --set-exit-if-changed lib/core/sync/projection_change_set.dart lib/features/notes/editor/sync/editor_operation_capture.dart lib/features/notes/editor/sync/note_operation_adapter.dart lib/features/notes/editor/sync/note_sync_session.dart lib/features/tasks/domain/projected_document.dart lib/features/tasks/domain/note_document_projector.dart lib/features/tasks/domain/task_projection_engine.dart lib/core/database/daos/tasks_dao.dart lib/core/database/database.dart test/core/sync/projection_change_set_test.dart test/core/database/daos/tasks_dao_test.dart test/features/tasks/domain/note_document_projector_test.dart test/features/tasks/domain/task_projection_engine_test.dart test/features/tasks/domain/task_projection_benchmark_test.dart test/features/notes/domain/editor_operation_capture_test.dart test/features/notes/domain/note_operation_adapter_test.dart test/features/notes/domain/note_sync_session_test.dart test/features/notes/domain/sync_characterization_test.dart integration_test/full_suite_test.dart
    rtk git diff --check

Expected: no formatting or whitespace errors.

- [ ] Step 2: Run focused suites sequentially

    rtk flutter test test/core/sync/projection_change_set_test.dart
    rtk flutter test test/core/database/daos/tasks_dao_test.dart
    rtk flutter test test/features/tasks/domain/note_document_projector_test.dart test/features/tasks/domain/task_projection_engine_test.dart test/features/tasks/domain/task_projection_benchmark_test.dart
    rtk flutter test test/features/notes/domain/editor_operation_capture_test.dart test/features/notes/domain/note_operation_adapter_test.dart test/features/notes/domain/note_sync_session_test.dart test/features/notes/domain/sync_characterization_test.dart
    rtk flutter test integration_test/full_suite_test.dart -d windows

Expected: every command exits 0; report counts and skips separately.

- [ ] Step 3: Run full Flutter checks

    rtk flutter analyze --no-fatal-infos
    rtk flutter test

Expected: analyzer and full suite exit 0. Existing non-failing warnings must be
listed, not hidden.

- [ ] Step 4: Run backend regression checks

From backend:

    rtk proxy powershell -NoProfile -Command "go vet ./..."
    rtk proxy powershell -NoProfile -Command "go test -count=1 -short ./..."
    rtk proxy powershell -NoProfile -Command "go build ./..."

No backend file is expected to change. Do not stage one unless a test proves a
required contract change.

- [ ] Step 5: Run Android CI-equivalent checks

With Flutter 3.44.1:

    rtk flutter pub get
    rtk flutter analyze --no-fatal-infos
    rtk flutter test
    rtk flutter build apk --debug --build-number=1 --android-project-arg shareLinkHost=supanotes.app

Run the unsigned app-bundle command separately and record its signing limitation
exactly as .github/workflows/android.yml does. The APK build must succeed.

- [ ] Step 6: Run the required code review

Use the code-review skill against the implementation base commit. Inspect
canonical ownership, local/remote/rebased convergence, structural suffixes,
transaction atomicity, rebuild reasons, telemetry privacy, oracle equality,
complexity, and file size. Fix every actionable finding with a failing test
first, then rerun its focused suite.

- [ ] Step 7: Verify real GitHub Actions results

Open a pull request or dispatch the applicable workflows and wait for fresh
results. Required checks are Android analyze/full test/APK and the Cognitive
Complexity Audit. Run Backend CI only if backend paths change. The iOS workflow
currently has on: []; do not claim an iOS CI result without an observed macOS
run.

Record workflow names, URLs, and statuses in walkthrough.md. A local green suite
is not evidence that GitHub CI is green.

- [ ] Step 8: Update task and walkthrough evidence

Record changed files, focused tests, E2E result, full Flutter count/skips,
analyzer, Android build, backend result, GitHub check URLs, and any environment
limitation.

- [ ] Step 9: Stage only implementation and evidence

Before staging:

    rtk git status --short
    rtk git diff --name-only

Exclude unrelated changes and generated files. Commit with:

    rtk git add lib/core/sync/projection_change_set.dart lib/features/notes/editor/sync/editor_operation_capture.dart lib/features/notes/editor/sync/note_operation_adapter.dart lib/features/notes/editor/sync/note_sync_session.dart lib/features/tasks/domain/projected_document.dart lib/features/tasks/domain/note_document_projector.dart lib/features/tasks/domain/task_projection_engine.dart lib/core/database/daos/tasks_dao.dart lib/core/database/database.dart test/core/sync/projection_change_set_test.dart test/core/database/daos/tasks_dao_test.dart test/features/tasks/domain/note_document_projector_test.dart test/features/tasks/domain/task_projection_engine_test.dart test/features/tasks/domain/task_projection_benchmark_test.dart test/features/notes/domain/editor_operation_capture_test.dart test/features/notes/domain/note_operation_adapter_test.dart test/features/notes/domain/note_sync_session_test.dart test/features/notes/domain/sync_characterization_test.dart integration_test/full_suite_test.dart docs/e2e-test-scenario-matrix.md task.md walkthrough.md
    rtk git commit -m "feat(tasks): project only affected note blocks"

Do not claim completion until fresh verification evidence and a clean staged path
are available.

## Self-review checklist

- [ ] Pure classifier, local capture, remote/rebased reconciliation, task
  selection, DAO transaction, session queue, telemetry, benchmark, E2E, full
  suite, and CI are covered.
- [ ] Every production change has a preceding failing test in its task.
- [ ] The full projection path remains the oracle and recovery path.
- [ ] content/excerpt still use every block.
- [ ] Unaffected task rows are not read or updated in the incremental path.
- [ ] Structural operations cover the required suffix.
- [ ] Unknown impact requests an explicit rebuild.
- [ ] No generated file, wire change, migration, compatibility path, or durable
  index is introduced.
- [ ] Flutter processes run sequentially.
- [ ] CI status comes from real GitHub results, not local inference.

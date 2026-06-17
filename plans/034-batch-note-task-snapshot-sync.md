# Plan 034: Batch note task snapshot sync

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report. Do not improvise. When done, update the status row for this plan
> in `plans/README.md` unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat fd87433..HEAD -- lib/features/notes/domain/task_entry.dart lib/features/notes/presentation/controllers/note_editor_controller.dart lib/features/notes/data/notes_repository.dart lib/features/tasks/data/local/tasks_local_repository.dart lib/core/database/daos/tasks_dao.dart test/features/notes/data/notes_repository_test.dart test/features/notes/data/markdown_serializer_test.dart test/serialization_test.dart`
>
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding. On a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: perf / correctness / tests
- **Planned at**: commit `fd87433`, 2026-06-17

## Why this matters

The note editor serializes rich editor state into Markdown and also extracts
inline `TaskNode`s into first-class task rows. Today that extraction loses the
visual task order and writes each task change one SQLite operation at a time
during autosave. For notes with many task widgets, every save can issue a
sequence of update/create/delete calls, and downstream task lists cannot rely
on `position` matching the order in the note. This plan makes the task snapshot
operation explicit, ordered, and batched, while replacing a non-assertive
serialization test with real coverage.

This plan does not remove persisted note titles. That larger data-contract
simplification is already tracked separately in `plans/028-remove-persisted-note-title.md`.

## Current state

- `lib/features/notes/domain/task_entry.dart` is the transfer object for tasks
  extracted from the editor document. It currently carries only id, text, and
  completion state:

```dart
class TaskEntry {
  final String id;
  final String text;
  final bool isComplete;

  const TaskEntry({
    required this.id,
    required this.text,
    required this.isComplete,
  });
}
```

- `lib/features/notes/presentation/controllers/note_editor_controller.dart`
  extracts task entries by iterating the document, but it does not record
  order:

```dart
  List<TaskEntry> _extractTasks(MutableDocument doc) {
    final tasks = <TaskEntry>[];
    for (final node in doc) {
      if (node is TaskNode) {
        tasks.add(
          TaskEntry(
            id: node.id,
            text: node.text.toPlainText(),
            isComplete: node.isComplete,
          ),
        );
      }
    }
    return tasks;
  }
```

- `lib/features/notes/data/notes_repository.dart` diffs task IDs and performs
  one awaited repository call per task:

```dart
  Future<void> syncTasksFromDocument(
    String noteId,
    List<TaskEntry> tasks,
  ) async {
    final currentTasks = await _tasksLocal.getNoteTasks(noteId);
    final currentIds = currentTasks.map((t) => t.id).toSet();
    final docIds = tasks.map((t) => t.id).toSet();

    for (final task in tasks) {
      if (currentIds.contains(task.id)) {
        await _tasksLocal.updateTask(
          TasksCompanion(
            id: Value(task.id),
            title: Value(task.text),
            status: Value(task.isComplete ? 'done' : 'open'),
          ),
        );
      } else {
        await _tasksLocal.createTask(
          id: task.id,
          noteId: noteId,
          title: task.text,
          position: 0,
          status: task.isComplete ? 'done' : 'open',
        );
      }
    }

    final removed = currentIds.difference(docIds);
    for (final id in removed) {
      await _tasksLocal.deleteTask(id);
    }
  }
```

- `test/serialization_test.dart` is not meaningful coverage. It prints output
  and has no `expect`; it also contains an escaped interpolation bug:

```dart
return '```\n\$text\n```';
...
print('=== ITERATION \$i ===');
print('Length: \${reserialized.length}');
```

- Domain rule from `.docs/CONTEXT.md`: tasks are first-class database entities
  rendered inline in notes. The editor reflects task state, and Markdown is an
  output format, not the source of truth for task state.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Focused notes repository tests | `flutter test test/features/notes/data/notes_repository_test.dart` | exit 0, all tests pass |
| Focused Markdown serializer tests | `flutter test test/features/notes/data/markdown_serializer_test.dart` | exit 0, all tests pass |
| Focused note editor controller tests | `flutter test test/features/notes/presentation/controllers/note_editor_controller_test.dart` | exit 0, all tests pass |
| Focused sync tests | `flutter test test/core/sync/sync_service_test.dart` | exit 0, all tests pass |

Do not run formatters over unrelated files. If `flutter analyze` reports
pre-existing unrelated auth/router warnings, do not expand this plan to fix
them.

## Scope

**In scope**:

- `lib/features/notes/domain/task_entry.dart`
- `lib/features/notes/presentation/controllers/note_editor_controller.dart`
- `lib/features/notes/data/notes_repository.dart`
- `lib/features/tasks/data/local/tasks_local_repository.dart`
- `lib/core/database/daos/tasks_dao.dart`
- `test/features/notes/data/notes_repository_test.dart`
- `test/features/notes/data/markdown_serializer_test.dart`
- `test/serialization_test.dart`

**Out of scope**:

- Removing persisted note titles. Use `plans/028-remove-persisted-note-title.md`.
- Changing the Markdown wire format for task IDs or divider metadata.
- Refactoring `NoteEditorController` lifecycle or `SaveThrottle`.
- Changing backend sync APIs.
- Changing task recurrence, due-date, or completion-history semantics.

## Git workflow

- Branch name: `fix/note-task-snapshot-sync`.
- Commit message style: conventional commits, for example
  `fix(notes): batch task snapshot sync`.
- Do not push or open a PR unless the operator explicitly asks.

## Steps

### Step 1: Add task position to the extracted editor DTO

Modify `lib/features/notes/domain/task_entry.dart` so `TaskEntry` carries the
task's document order:

```dart
class TaskEntry {
  final String id;
  final String text;
  final bool isComplete;
  final int position;

  const TaskEntry({
    required this.id,
    required this.text,
    required this.isComplete,
    required this.position,
  });
}
```

Modify `_extractTasks` in
`lib/features/notes/presentation/controllers/note_editor_controller.dart` so
position increments only for task nodes:

```dart
  List<TaskEntry> _extractTasks(MutableDocument doc) {
    final tasks = <TaskEntry>[];
    var position = 0;
    for (final node in doc) {
      if (node is TaskNode) {
        tasks.add(
          TaskEntry(
            id: node.id,
            text: node.text.toPlainText(),
            isComplete: node.isComplete,
            position: position,
          ),
        );
        position++;
      }
    }
    return tasks;
  }
```

Update all test call sites that construct `TaskEntry` to pass `position`.

**Verify**:
`rg -n "TaskEntry\\(" lib test`

Expected: every `TaskEntry(` call includes `position:`.

**Verify**:
`flutter test test/features/notes/presentation/controllers/note_editor_controller_test.dart`

Expected: exit 0. If tests fail only because existing expectations now need to
assert `position`, update the test expectation to match the document order.

### Step 2: Add a batched DAO operation for replacing a note's task snapshot

Modify `lib/core/database/daos/tasks_dao.dart`. Add a method that accepts the
note id, user id, and extracted tasks, then updates existing rows, inserts new
rows, and hard-deletes rows removed from the editor in a single transaction.

Because `TasksDao` lives in `core/database` and should not import
`features/notes/domain/task_entry.dart`, define a small local DTO in
`tasks_dao.dart`:

```dart
class TaskSnapshotEntry {
  const TaskSnapshotEntry({
    required this.id,
    required this.title,
    required this.status,
    required this.position,
  });

  final String id;
  final String title;
  final String status;
  final int position;
}
```

Add this method to `TasksDao`:

```dart
  Future<void> replaceNoteTaskSnapshot({
    required String noteId,
    required String userId,
    required List<TaskSnapshotEntry> entries,
  }) async {
    final now = DateTime.now().toUtc();
    final current = await (select(tasks)..where((t) => t.noteId.equals(noteId))).get();
    final currentIds = current.map((t) => t.id).toSet();
    final incomingIds = entries.map((t) => t.id).toSet();

    await transaction(() async {
      await batch((b) {
        for (final entry in entries) {
          if (currentIds.contains(entry.id)) {
            b.update(
              tasks,
              TasksCompanion(
                title: Value(entry.title),
                status: Value(entry.status),
                position: Value(entry.position),
                updatedAt: Value(now),
                isDirty: const Value(true),
              ),
              where: (t) => t.id.equals(entry.id),
            );
          } else {
            b.insert(
              tasks,
              TaskData(
                id: entry.id,
                userId: userId,
                noteId: noteId,
                title: entry.title,
                status: entry.status,
                position: entry.position,
                createdAt: now,
                updatedAt: now,
                deletedAt: null,
                isDirty: true,
              ),
              mode: InsertMode.replace,
            );
          }
        }

        for (final id in currentIds.difference(incomingIds)) {
          b.deleteWhere(tasks, (t) => t.id.equals(id));
        }
      });
    });
  }
```

Keep `deleteTaskById`, `updateTask`, and `createTask` for existing callers.
This plan only routes editor snapshot saves through the new batched path.

**Verify**:
`dart analyze lib/core/database/daos/tasks_dao.dart`

Expected: exit 0 for this file. If `Batch.deleteWhere` is unavailable in the
installed Drift version, STOP and report; do not rewrite a large alternative
without review.

### Step 3: Route editor task snapshot sync through the batched operation

Modify `lib/features/tasks/data/local/tasks_local_repository.dart`. Add a
public method that maps feature-layer task snapshot entries into the DAO DTO:

```dart
  Future<void> replaceNoteTaskSnapshot({
    required String noteId,
    required List<TaskSnapshotEntry> entries,
  }) {
    return _dao.replaceNoteTaskSnapshot(
      noteId: noteId,
      userId: _userId,
      entries: entries,
    );
  }
```

Modify `lib/features/notes/data/notes_repository.dart`.

Remove the manual diff loop inside `syncTasksFromDocument` and replace it with
a single call:

```dart
  @override
  Future<void> syncTasksFromDocument(
    String noteId,
    List<TaskEntry> tasks,
  ) {
    return _tasksLocal.replaceNoteTaskSnapshot(
      noteId: noteId,
      entries: tasks
          .map(
            (task) => TaskSnapshotEntry(
              id: task.id,
              title: task.text,
              status: task.isComplete ? 'done' : 'open',
              position: task.position,
            ),
          )
          .toList(growable: false),
    );
  }
```

Keep `saveNoteSnapshot` sequencing the same: tasks are synced before the note
content update. Do not change title handling in this plan.

**Verify**:
`rg -n "for \\(final task in tasks\\)|position: 0,|deleteTask\\(id\\)" lib/features/notes/data/notes_repository.dart`

Expected: no matches for the old editor snapshot loop.

### Step 4: Add repository tests for ordered, batched task snapshot behavior

Modify `test/features/notes/data/notes_repository_test.dart`.

Expand `FakeTasksLocalRepository` so it records one snapshot call rather than
silently ignoring task writes. Add these fields:

```dart
  int replaceSnapshotCalls = 0;
  String? replacedNoteId;
  List<TaskSnapshotEntry> replacedEntries = const [];
```

Add this override:

```dart
  @override
  Future<void> replaceNoteTaskSnapshot({
    required String noteId,
    required List<TaskSnapshotEntry> entries,
  }) async {
    replaceSnapshotCalls++;
    replacedNoteId = noteId;
    replacedEntries = List<TaskSnapshotEntry>.from(entries);
  }
```

Update the existing `saveSnapshot writes title content and tasks together`
test to include two `TaskEntry`s with non-zero order:

```dart
      await repo.saveNoteSnapshot(
        id: 'note-1',
        title: 'A',
        content: 'B',
        tasks: const [
          TaskEntry(
            id: 'task-1',
            text: 'First',
            isComplete: false,
            position: 0,
          ),
          TaskEntry(
            id: 'task-2',
            text: 'Second',
            isComplete: true,
            position: 1,
          ),
        ],
      );

      expect(tasksLocal.replaceSnapshotCalls, 1);
      expect(tasksLocal.replacedNoteId, 'note-1');
      expect(tasksLocal.replacedEntries.map((t) => t.id), ['task-1', 'task-2']);
      expect(tasksLocal.replacedEntries.map((t) => t.position), [0, 1]);
      expect(tasksLocal.replacedEntries.map((t) => t.status), ['open', 'done']);
```

If the fake class currently has `createTask`, `updateTask`, and `deleteTask`
methods that are no longer used by this test, leave them as no-op overrides if
the interface still requires them. Do not delete interface methods used by other
features.

**Verify**:
`flutter test test/features/notes/data/notes_repository_test.dart`

Expected: exit 0, including the updated snapshot test.

### Step 5: Add DAO-level coverage for update, insert, delete, and position

Create or modify the closest DAO test file for tasks. Prefer
`test/core/database/daos/tasks_dao_test.dart` because it already covers task DAO
behavior.

Add a test named:
`replaceNoteTaskSnapshot updates inserts deletes and preserves order`.

Use the existing test setup style in that file. The test should:

1. Create a test database.
2. Insert a note row for `note-1`.
3. Insert two existing tasks for `note-1`: `task-keep` and `task-remove`.
4. Call `db.tasksDao.replaceNoteTaskSnapshot(...)` with entries:
   - `task-keep`, title changed, status `done`, position `0`
   - `task-new`, title `New`, status `open`, position `1`
5. Query tasks for `note-1`.
6. Assert:
   - `task-remove` is absent.
   - `task-keep` has changed title/status/position and `isDirty == true`.
   - `task-new` exists with `position == 1`, `userId == test-user`, and
     `isDirty == true`.

The exact helper names may differ in the existing test file; match the current
fixture style instead of creating a second database helper.

**Verify**:
`flutter test test/core/database/daos/tasks_dao_test.dart`

Expected: exit 0, including the new DAO test.

### Step 6: Replace the non-assertive serialization test

Do not keep `test/serialization_test.dart` as a print-only test.

Move any useful coverage into
`test/features/notes/data/markdown_serializer_test.dart`. Add an assertive test
for fenced code blocks if the current app supports preserving them through
`parseNoteToMarkdown` and `serializeNoteToMarkdown`.

Use this shape:

```dart
    test('fenced code blocks round-trip without literal interpolation artifacts', () {
      const original = '''Before

```
Line A
Line B
```

After''';

      final saved = serializeNoteToMarkdown(parseNoteToMarkdown(original));

      expect(saved, isNot(contains(r'$text')));
      expect(saved, contains('Line A'));
      expect(saved, contains('Line B'));
    });
```

If the current serializer intentionally does not support fenced code block
round-tripping, do not fake support in a test. Instead, delete
`test/serialization_test.dart` and record in the PR summary that fenced-code
round-trip is out of scope for the current Markdown codec.

After moving useful assertions, delete `test/serialization_test.dart`.
The root script `test_serialization.dart` is a local scratch artifact; remove it
only if the operator confirms it is not intentionally kept. This plan does not
require deleting it.

**Verify**:
`flutter test test/features/notes/data/markdown_serializer_test.dart`

Expected: exit 0. There should be no print-only serialization test left under
`test/`.

**Verify**:
`rg -n "print\\(|Markdown serialization stability|\\$text" test/serialization_test.dart test/features/notes/data/markdown_serializer_test.dart`

Expected: `test/serialization_test.dart` does not exist. The remaining
serializer test file has no `$text` artifact from the old fake serializer.

### Step 7: Run focused regression checks

Run the focused tests that cover this plan:

```powershell
flutter test test/features/notes/data/notes_repository_test.dart
flutter test test/core/database/daos/tasks_dao_test.dart
flutter test test/features/notes/data/markdown_serializer_test.dart
flutter test test/features/notes/presentation/controllers/note_editor_controller_test.dart
flutter test test/core/sync/sync_service_test.dart
```

Expected: every command exits 0.

Then inspect the diff:

```powershell
git diff --stat
git diff -- lib/features/notes/domain/task_entry.dart lib/features/notes/presentation/controllers/note_editor_controller.dart lib/features/notes/data/notes_repository.dart lib/features/tasks/data/local/tasks_local_repository.dart lib/core/database/daos/tasks_dao.dart test/features/notes/data/notes_repository_test.dart test/features/notes/data/markdown_serializer_test.dart test/core/database/daos/tasks_dao_test.dart test/serialization_test.dart
```

Expected: only in-scope files changed. If additional generated Drift files
changed, STOP and report; this plan does not require schema or codegen changes.

## Test plan

- `test/features/notes/data/notes_repository_test.dart`: prove
  `saveNoteSnapshot` delegates task rows as one ordered snapshot and preserves
  the note content/title update behavior.
- `test/core/database/daos/tasks_dao_test.dart`: prove the new DAO operation
  updates existing tasks, inserts new tasks, deletes removed tasks, writes
  `position`, and marks changed rows dirty.
- `test/features/notes/data/markdown_serializer_test.dart`: keep the existing
  Markdown round-trip coverage passing and add or consolidate assertive coverage
  for the old print-only serialization scenario.
- Existing focused tests for note editor controller and sync mapper must remain
  green.

## Done criteria

- [ ] `TaskEntry` includes `position`.
- [ ] `_extractTasks` assigns zero-based positions in document order, counting
      only `TaskNode`s.
- [ ] `syncTasksFromDocument` no longer performs per-task awaited
      update/create/delete loops.
- [ ] `TasksDao` has a single transaction/batch operation for replacing a
      note's task snapshot.
- [ ] Existing task repository callers still compile; no backend API changes.
- [ ] `test/serialization_test.dart` is removed or converted into meaningful
      assertions under `test/features/notes/data/markdown_serializer_test.dart`.
- [ ] All focused verification commands in Step 7 pass.
- [ ] `plans/README.md` status row for 034 is updated when implementation is
      complete.

## STOP conditions

Stop and report back if:

- `Batch.deleteWhere` or equivalent batched deletion is not available in the
  installed Drift API and the alternative would require a larger DAO rewrite.
- The live `TaskEntry`, `_extractTasks`, or `syncTasksFromDocument` code no
  longer matches the excerpts above.
- Updating the fake repositories reveals that `TasksLocalRepository` is not
  mockable/subclassable in the current test structure.
- Fixing the serializer test requires changing the Markdown wire format for
  tasks, dividers, or code blocks.
- Any step requires touching backend sync contracts, migrations, or generated
  Drift files.

## Maintenance notes

- Reviewers should scrutinize the delete behavior. This plan keeps the current
  semantics: removing a task widget from the note hard-deletes the local task
  row through the editor snapshot path. It does not change app-level task
  deletion semantics.
- If note content later supports collaborative editing or conflict resolution,
  the task snapshot operation should become conflict-aware rather than blindly
  replacing the task set.
- If `plans/028-remove-persisted-note-title.md` lands later, re-run the
  repository tests from this plan because both plans touch `saveNoteSnapshot`.

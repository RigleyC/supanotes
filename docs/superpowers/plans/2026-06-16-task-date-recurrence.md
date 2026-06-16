# Task Due Date and Recurrence Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct task due date timezone drift, enable instant visual updates of task date/recurrence badges in the editor, correctly schedule recurring tasks upon editor checkbox completion, and fix the "overdue" styling for completed tasks.

**Architecture:** We will use local timezone conversion on model boundaries, subclass the SuperEditor `TaskComponentViewModel` to trigger reactive view updates, bubble up checkbox completion events to the repository, and update the metadata badge widget with completion status.

**Tech Stack:** Flutter, SuperEditor, Drift (SQLite), Riverpod

---

### Task 1: Timezone Drift Alignment in TaskModel

**Files:**
- Modify: [task_model.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/tasks/domain/task_model.dart:40-60)

- [ ] **Step 1: Write local timezone mapping in model**

Replace `TaskModel.fromData` implementation to convert `dueDate` from UTC to local time:

```dart
  factory TaskModel.fromData(TaskData d) {
    return TaskModel(
      id: d.id,
      userId: d.userId,
      noteId: d.noteId,
      title: d.title,
      status: d.status,
      position: d.position,
      dueDate: d.dueDate?.toLocal(),
      completedAt: d.completedAt?.toLocal(),
      recurrence: d.recurrence,
      createdAt: d.createdAt.toLocal(),
      updatedAt: d.updatedAt.toLocal(),
    );
  }
```

- [ ] **Step 2: Verify existing tests pass**

Run: `flutter test test/features/tasks/domain/task_date_filter_test.dart`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add lib/features/tasks/domain/task_model.dart
git commit -m "feat(tasks): convert database UTC dates to local timezone in TaskModel"
```

---

### Task 2: Subclass TaskComponentViewModel for SuperEditor Rebuilds

**Files:**
- Modify: [custom_task_component.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/widgets/custom_task_component.dart:1-80)

- [ ] **Step 1: Create CustomTaskComponentViewModel class and update Builder**

Add `CustomTaskComponentViewModel` subclass at the bottom of the file (or right above builders) and modify `CustomTaskComponentBuilder` to instantiate it.

Add class:
```dart
class CustomTaskComponentViewModel extends TaskComponentViewModel {
  CustomTaskComponentViewModel({
    required super.nodeId,
    required super.createdAt,
    required super.padding,
    required super.indent,
    required super.isComplete,
    required super.setComplete,
    required super.text,
    required super.textDirection,
    required super.textAlignment,
    required super.textStyleBuilder,
    required super.selectionColor,
    this.dueDate,
    this.recurrence,
  });

  final DateTime? dueDate;
  final TaskRecurrence? recurrence;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CustomTaskComponentViewModel) return false;
    if (!super.operator ==(other)) return false;
    return dueDate == other.dueDate && recurrence == other.recurrence;
  }

  @override
  int get hashCode => Object.hash(super.hashCode, dueDate, recurrence);
}
```

Update `CustomTaskComponentBuilder.createViewModel` to return `CustomTaskComponentViewModel` instead of `TaskComponentViewModel`:
```dart
  @override
  TaskComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is! TaskNode) return null;
    if (hideCompleted && node.isComplete) return null;

    final metadata = taskMetadataById[node.id];

    return CustomTaskComponentViewModel(
      nodeId: node.id,
      createdAt: node.metadata[NodeMetadata.createdAt],
      padding: EdgeInsets.zero,
      indent: node.indent,
      isComplete: node.isComplete,
      setComplete: (bool isComplete) {
        _editor.execute([
          ChangeTaskCompletionRequest(nodeId: node.id, isComplete: isComplete),
        ]);
      },
      text: node.text,
      textDirection: getParagraphDirection(node.text.toPlainText()),
      textAlignment: TextAlign.left,
      textStyleBuilder: noStyleBuilder,
      selectionColor: const Color(0x00000000),
      dueDate: metadata?.dueDate,
      recurrence: metadata?.recurrence,
    );
  }
```

Update `CustomTaskComponentBuilder.createComponent`:
```dart
  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is! TaskComponentViewModel) return null;

    final taskMeta = componentViewModel is CustomTaskComponentViewModel
        ? taskMetadataById[componentViewModel.nodeId]
        : null;

    return CustomTaskComponent(
      key: componentContext.componentKey,
      viewModel: componentViewModel,
      taskMetadata: taskMeta ?? taskMetadataById[componentViewModel.nodeId],
      onLongPress: onTaskLongPress == null
          ? null
          : () => onTaskLongPress!(componentViewModel.nodeId),
    );
  }
```

- [ ] **Step 2: Verify the project compiles**

Run: `flutter test test/features/notes/presentation/note_editor_screen_test.dart`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add lib/features/notes/presentation/widgets/custom_task_component.dart
git commit -m "feat(notes): create CustomTaskComponentViewModel subclass to reactively rebuild tasks on metadata changes"
```

---

### Task 3: Bubbling Task Complete/Reopen Actions from NoteEditor

**Files:**
- Modify: [note_editor.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/widgets/note_editor.dart:20-45)
- Modify: [note_editor_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/note_editor_screen.dart:120-135)
- Modify: [inbox_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/inbox_screen.dart:120-135)

- [ ] **Step 1: Declare callbacks in NoteEditor**

In `lib/features/notes/presentation/widgets/note_editor.dart`, add callbacks to the `NoteEditor` constructor and fields:

```dart
  final void Function(String taskId)? onTaskComplete;
  final void Function(String taskId)? onTaskReopen;

  const NoteEditor({
    super.key,
    required this.noteId,
    required this.content,
    this.title,
    required this.taskMetadata,
    this.hideCompleted = false,
    required this.snapshotSave,
    this.emptyNoteExit,
    this.onHasContentChanged,
    this.onTaskLongPress,
    this.onTaskComplete,
    this.onTaskReopen,
  });
```

- [ ] **Step 2: Wire callbacks in NoteEditorScreen**

In `lib/features/notes/presentation/note_editor_screen.dart`, instantiate `NoteEditor` with the callbacks calling repository methods:

```dart
        child: NoteEditor(
          noteId: widget.noteId,
          content: note.content,
          title: note.title,
          taskMetadata: tasksMap,
          hideCompleted: note.hideCompleted,
          snapshotSave: (noteId, title, markdown, tasks) =>
              defaultSnapshotSave(repo, noteId, title, markdown, tasks),
          emptyNoteExit: (noteId) => defaultEmptyNoteExit(repo, noteId),
          onTaskLongPress: (taskId, flushSnapshot) =>
              _openTaskActions(taskId, flushSnapshot),
          onTaskComplete: (taskId) =>
              ref.read(tasksRepositoryProvider).completeTask(taskId),
          onTaskReopen: (taskId) =>
              ref.read(tasksRepositoryProvider).reopenTask(taskId),
        ),
```

- [ ] **Step 3: Wire callbacks in InboxScreen**

In `lib/features/notes/presentation/inbox_screen.dart`, instantiate `NoteEditor` with the callbacks:

```dart
        child: NoteEditor(
          noteId: noteId,
          content: inbox.content,
          title: inbox.title,
          taskMetadata: tasksMap,
          snapshotSave: (noteId, title, markdown, tasks) =>
              defaultSnapshotSave(repo, noteId, title, markdown, tasks),
          onHasContentChanged: (hasContent) {
            if (mounted) setState(() => _hasContent = hasContent);
          },
          onTaskLongPress: (taskId, flushSnapshot) =>
              _openTaskActions(taskId, flushSnapshot),
          onTaskComplete: (taskId) =>
              ref.read(tasksRepositoryProvider).completeTask(taskId),
          onTaskReopen: (taskId) =>
              ref.read(tasksRepositoryProvider).reopenTask(taskId),
        ),
```

- [ ] **Step 4: Verify compiling**

Run: `flutter test test/features/notes/presentation/note_editor_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/notes/presentation/widgets/note_editor.dart lib/features/notes/presentation/note_editor_screen.dart lib/features/notes/presentation/inbox_screen.dart
git commit -m "feat(notes): wire onTaskComplete and onTaskReopen callbacks from screens to NoteEditor"
```

---

### Task 4: Complete/Reopen Triggering and Recurrence Reset in Editor

**Files:**
- Modify: [custom_task_component.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/widgets/custom_task_component.dart:12-45)
- Modify: [note_editor.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/widgets/note_editor.dart:160-176)

- [ ] **Step 1: Pass callbacks to CustomTaskComponentBuilder**

In `lib/features/notes/presentation/widgets/note_editor.dart`, pass callbacks from widget fields down to `CustomTaskComponentBuilder`:

```dart
                        CustomTaskComponentBuilder(
                          controller.editor!,
                          taskMetadataById: widget.taskMetadata,
                          hideCompleted: widget.hideCompleted,
                          onTaskLongPress: (taskId) =>
                              widget.onTaskLongPress?.call(
                                taskId,
                                () => controller.persistSnapshotNow(),
                              ),
                          onTaskComplete: widget.onTaskComplete,
                          onTaskReopen: widget.onTaskReopen,
                        ),
```

Update `CustomTaskComponentBuilder` class properties to receive them:
```dart
  CustomTaskComponentBuilder(
    this._editor, {
    this.taskMetadataById = const {},
    this.hideCompleted = false,
    this.onTaskLongPress,
    this.onTaskComplete,
    this.onTaskReopen,
  });

  final Editor _editor;
  final Map<String, TaskModel> taskMetadataById;
  final bool hideCompleted;
  final ValueChanged<String>? onTaskLongPress;
  final void Function(String taskId)? onTaskComplete;
  final void Function(String taskId)? onTaskReopen;
```

- [ ] **Step 2: Update setComplete inside Builder to fire callbacks and handle recurrence**

Update `createViewModel` to execute the database callbacks and schedule the recurrence checkbox reset if the task is recurring:

```dart
      setComplete: (bool isComplete) {
        _editor.execute([
          ChangeTaskCompletionRequest(nodeId: node.id, isComplete: isComplete),
        ]);

        if (isComplete) {
          onTaskComplete?.call(node.id);
        } else {
          onTaskReopen?.call(node.id);
        }

        final taskMeta = taskMetadataById[node.id];
        if (isComplete && taskMeta?.recurrence != null) {
          // Task is recurring! Reset the checkbox to unchecked in the editor after 400ms.
          Future.delayed(const Duration(milliseconds: 400), () {
            final exists = document.getNodeById(node.id) != null;
            if (exists) {
              _editor.execute([
                ChangeTaskCompletionRequest(nodeId: node.id, isComplete: false),
              ]);
            }
          });
        }
      },
```

- [ ] **Step 3: Run all existing tests**

Run: `flutter test`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add lib/features/notes/presentation/widgets/custom_task_component.dart lib/features/notes/presentation/widgets/note_editor.dart
git commit -m "feat(notes): trigger repository task completion callbacks and schedule recurrence reset in editor task component builder"
```

---

### Task 5: Muted Overdue Badge for Completed Tasks

**Files:**
- Modify: [task_metadata_badges.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/tasks/presentation/widgets/task_metadata_badges.dart:10-70)
- Modify: [custom_task_component.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/widgets/custom_task_component.dart:130-155)
- Modify: [task_tile.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/tasks/presentation/widgets/task_tile.dart:120-132)
- Modify: [task_metadata_badges_test.dart](file:///c:/Users/rigleyc/projects/supanotes/test/features/tasks/presentation/widgets/task_metadata_badges_test.dart:30-40)

- [ ] **Step 1: Update TaskMetadataBadges class definition and label/color logic**

Modify `TaskMetadataBadges` constructor to take `isCompleted`:

```dart
class TaskMetadataBadges extends StatelessWidget {
  const TaskMetadataBadges({
    super.key,
    this.dueDate,
    this.recurrence,
    this.isCompleted = false,
  });

  final DateTime? dueDate;
  final TaskRecurrence? recurrence;
  final bool isCompleted;
```

Update `_dueDateLabel` and `_dueDateColor` inside [task_metadata_badges.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/tasks/presentation/widgets/task_metadata_badges.dart):

```dart
  String _dueDateLabel(DateTime dueDate) {
    final today = DateTime.now().startOfDay;
    final date = dueDate.startOfDay;

    if (date.isSameDayAs(today)) return 'Hoje';
    if (date.isBefore(today)) {
      if (isCompleted) {
        return DateFormat('d MMM').format(dueDate);
      }
      return 'Atrasada \u00b7 ${DateFormat('d MMM').format(dueDate)}';
    }
    return DateFormat('d MMM').format(dueDate);
  }

  Color _dueDateColor(BuildContext context, DateTime dueDate) {
    if (isCompleted) {
      return Theme.of(context).colorScheme.onSurfaceVariant;
    }

    final today = DateTime.now().startOfDay;
    final date = dueDate.startOfDay;
    
    if (date.isBefore(today)) return Theme.of(context).colorScheme.error;
    if (date.isSameDayAs(today)) return AppColors.success;
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }
```

- [ ] **Step 2: Pass isCompleted in CustomTaskComponent**

Modify [custom_task_component.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/widgets/custom_task_component.dart) call site to supply `isCompleted`:

```dart
                  if (widget.taskMetadata?.dueDate != null ||
                      widget.taskMetadata?.recurrence != null) ...[
                    const SizedBox(height: 4),
                    TaskMetadataBadges(
                      dueDate: widget.taskMetadata?.dueDate,
                      recurrence: widget.taskMetadata?.recurrence,
                      isCompleted: widget.viewModel.isComplete,
                    ),
                  ],
```

- [ ] **Step 3: Pass isCompleted in TaskTile**

Modify [task_tile.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/tasks/presentation/widgets/task_tile.dart) call site:

```dart
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.task});
  final TaskModel task;

  @override
  Widget build(BuildContext context) {
    return TaskMetadataBadges(
      dueDate: task.dueDate,
      recurrence: task.recurrence,
      isCompleted: task.isCompleted,
    );
  }
}
```

- [ ] **Step 4: Add widget test for completed overdue badge styling**

Add a test case in `test/features/tasks/presentation/widgets/task_metadata_badges_test.dart` verifying completed past tasks display normally (without "Atrasada"):

```dart
  testWidgets('does not show Atrasada for past due dates when completed', (
    tester,
  ) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));

    await tester.pumpWidget(
      wrap(TaskMetadataBadges(dueDate: yesterday, isCompleted: true)),
    );

    expect(find.byIcon(Icons.event_outlined), findsOneWidget);
    expect(find.textContaining('Atrasada'), findsNothing);
  });
```

- [ ] **Step 5: Run all widget tests**

Run: `flutter test test/features/tasks/presentation/widgets/task_metadata_badges_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/features/tasks/presentation/widgets/task_metadata_badges.dart lib/features/notes/presentation/widgets/custom_task_component.dart lib/features/tasks/presentation/widgets/task_tile.dart test/features/tasks/presentation/widgets/task_metadata_badges_test.dart
git commit -m "feat(tasks): style past due dates as muted and not overdue when tasks are completed"
```

# Spec: Task Due Date and Recurrence Improvements

## Goal
To improve the user experience and correctness of task due dates and recurrence patterns. Specifically:
1. Ensure real-time visual updates of task metadata badges in the editor.
2. Fix timezone drift causing due dates to appear shifted by a day.
3. Correctly trigger recurrence rescheduling when completing tasks inside the note editor.
4. Correctly display past due dates of completed tasks as completed (muted) instead of overdue (red).

## Design Details

### 1. View Model Rebuild and Custom Subclass
In [custom_task_component.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/widgets/custom_task_component.dart), we will create a subclass of `TaskComponentViewModel` called `CustomTaskComponentViewModel` which adds the task's due date and recurrence rule, and overrides equality checks:
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
In `CustomTaskComponentBuilder.createViewModel`, we will return `CustomTaskComponentViewModel` populated with the current due date and recurrence from `taskMetadataById`.

### 2. Timezone Fix
To prevent timezone offset drift on the frontend, in `TaskModel.fromData` inside [task_model.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/tasks/domain/task_model.dart), we will convert the UTC `DateTime` retrieved from Drift back to the local timezone immediately:
```dart
dueDate: d.dueDate?.toLocal(),
```

### 3. Database Completion and Recurrence Triggers in Editor
We will update `NoteEditor` to accept callbacks for completing and reopening tasks:
```dart
final void Function(String taskId)? onTaskComplete;
final void Function(String taskId)? onTaskReopen;
```
These callbacks will be implemented in `NoteEditorScreen` and `InboxScreen` by delegating to `tasksRepository.completeTask` and `tasksRepository.reopenTask`.

In `CustomTaskComponentBuilder.createViewModel`'s `setComplete` callback:
1. We will call the standard editor request `ChangeTaskCompletionRequest` to update the document state.
2. We will call `onTaskComplete` or `onTaskReopen` to trigger the database completion logic (which handles completions history and recurrence scheduling).
3. If `isComplete` is true and the task is recurring, we will schedule a `Future.delayed` of **400ms** to programmatically reset the checkbox inside the editor using `ChangeTaskCompletionRequest(nodeId: node.id, isComplete: false)`. This lets the task reset back to unchecked while displaying the advanced due date.

### 4. Correcting "Overdue" Display for Completed Tasks
We will update `TaskMetadataBadges` in [task_metadata_badges.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/tasks/presentation/widgets/task_metadata_badges.dart) to accept `isCompleted` (defaulting to `false`):
```dart
class TaskMetadataBadges extends StatelessWidget {
  const TaskMetadataBadges({
    super.key,
    this.dueDate,
    this.recurrence,
    this.isCompleted = false,
  });

  final bool isCompleted;
  ...
```
* In `_dueDateLabel`: If `isCompleted` is true, we never append the "Atrasada" prefix and instead format the date normally.
* In `_dueDateColor`: If `isCompleted` is true, we return a muted/neutral color `Theme.of(context).colorScheme.onSurfaceVariant` instead of the error/success colors.

We will pass the completion status to `TaskMetadataBadges` from its call sites:
- In `CustomTaskComponent`: `isCompleted: widget.viewModel.isComplete`
- In `TaskTile`: `isCompleted: task.isCompleted`

## Verification Plan

### Manual Verification
1. **Timezone validation**: Change the task due date to today. Verify it is shown as "Hoje" and not "Atrasada".
2. **Real-time update**: Open the task actions sheet by long pressing the checkbox, select a due date (e.g. tomorrow), and press "Salvar". Verify the new date badge appears immediately below the task in the editor.
3. **Recurrence completion**: Set a task to "Diária" (Daily) due today. Toggle its checkbox. Verify it checks itself, waits 400ms, then unchecks itself and updates the badge to tomorrow's date.
4. **Muted overdue on complete**: Create a task due yesterday. Verify the badge shows "Atrasada" in red. Mark the task as completed. Verify the badge changes to a muted grey and no longer shows "Atrasada".

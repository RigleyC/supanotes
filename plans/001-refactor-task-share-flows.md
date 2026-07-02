# Plan 001: Refactor Task Metadata and Share UI Flows to Controller-Driven State

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat d9ddf89..HEAD -- lib/features/tasks/presentation/widgets/task_edit_sheet.dart lib/features/tasks/presentation/widgets/task_metadata_sheet.dart lib/features/notes/presentation/controllers/share_note_controller.dart lib/features/notes/presentation/widgets/share_note_sheet.dart lib/features/notes/presentation/widgets/share_list_section.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit `d9ddf89`, 2026-07-02

## Why this matters

The domain rule dictates that **task titles are edited and tasks are deleted exclusively via the rich-text editor**. Therefore, `TaskEditSheet` is conceptual dead code. We only need `TaskMetadataSheet` for managing task attributes (due date and recurrence). 

Additionally, the Task Metadata and Share flows currently leak state: the UI sheets mutate repositories directly, maintain local `_saving` variables, and orchestrate UI errors manually instead of relying on Riverpod controllers. Unifying these fixes architecture leaks and aligns the codebase with Riverpod best practices.

## Current state

- `lib/features/tasks/presentation/widgets/task_edit_sheet.dart` — Dead code that allows editing title/deleting tasks. Needs deletion.
- `lib/features/tasks/presentation/widgets/task_metadata_sheet.dart` — The correct sheet, but it manually invokes `tasksRepositoryProvider` instead of a controller.
- `lib/features/notes/presentation/controllers/share_note_controller.dart` — Currently only handles `share`. Needs `revoke`.
- `lib/features/notes/presentation/widgets/share_note_sheet.dart` — Uses raw `TextField` instead of `AppInput`, manages raw error state.
- `lib/features/notes/presentation/widgets/share_list_section.dart` — Uses manual loop instead of `ListView.separated`, bypasses controller for revoke.
- Repo conventions: "Dialogs de confirmação: use `showConfirmDialog(...)` de `confirm_dialog.dart` — PROIBIDO `showDialog` + `AlertDialog` inline" from AGENTS.md. "Use sempre os componentes compartilhados do app: AppInput".

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Typecheck | `flutter analyze`        | exit 0, no issues   |

## Scope

**In scope**:
- `lib/features/tasks/presentation/controllers/task_controller.dart` (create)
- `lib/features/tasks/presentation/widgets/task_edit_sheet.dart` (delete)
- `lib/features/tasks/presentation/widgets/task_metadata_sheet.dart` (refactor)
- `lib/features/notes/presentation/controllers/share_note_controller.dart`
- `lib/features/notes/presentation/widgets/share_note_sheet.dart`
- `lib/features/notes/presentation/widgets/share_list_section.dart`

**Out of scope**:
- Drift database models or repositories.
- `TaskModel` and `ShareModel` definitions.
- Editor task nodes logic.

## Git workflow

- Commit per step or per logical unit. Message style: conventional commits (e.g., `refactor(tasks): use TaskController in TaskMetadataSheet`).

## Steps

### Step 1: Create TaskController

Create `lib/features/tasks/presentation/controllers/task_controller.dart`. 
It should provide a standard Riverpod `AsyncNotifier` named `TaskController` handling `updateTaskMetadata` by injecting `tasksRepositoryProvider`.

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/tasks_repository.dart';
import '../../domain/task_recurrence.dart';

final taskControllerProvider = AsyncNotifierProvider.autoDispose<TaskController, void>(
  TaskController.new,
);

class TaskController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> updateTaskMetadata({
    required String taskId,
    required String title,
    DateTime? dueDate,
    TaskRecurrence? recurrence,
    bool clearDueDate = false,
    bool clearRecurrence = false,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(tasksRepositoryProvider).updateTask(
            taskId,
            title: title, // Title is passed only to satisfy the repository signature, but it shouldn't change
            dueDate: dueDate,
            recurrence: recurrence,
            clearDueDate: clearDueDate,
            clearRecurrence: clearRecurrence,
          ),
    );
  }
}
```

**Verify**: `flutter analyze` → No issues

### Step 2: Delete TaskEditSheet

1. Delete the unused file `lib/features/tasks/presentation/widgets/task_edit_sheet.dart`.

**Verify**: `flutter analyze` → No issues

### Step 3: Refactor TaskMetadataSheet

Modify `lib/features/tasks/presentation/widgets/task_metadata_sheet.dart` to:
1. Import `../controllers/task_controller.dart`.
2. Delete the direct usage of `tasksRepositoryProvider` and manual `TaskModel` reconstruction in `_onSave`, calling `ref.read(taskControllerProvider.notifier).updateTaskMetadata` instead.
3. Check `taskControllerProvider.isLoading` for the buttons.

```dart
  Future<void> _onSave() async {
    final controller = ref.read(taskControllerProvider.notifier);
    
    await controller.updateTaskMetadata(
      taskId: widget.task.id,
      title: widget.task.title,
      dueDate: _dueDate,
      recurrence: _recurrence,
      clearDueDate: _dueDate == null,
      clearRecurrence: _recurrence == null,
    );

    if (ref.read(taskControllerProvider).hasError) {
      if (mounted) AppMessenger.showError('Erro ao salvar tarefa');
      return;
    }
    
    // We no longer return the TaskModel, the Riverpod stream will update the UI automatically.
    if (mounted) Navigator.pop(context);
  }
```

**Verify**: `flutter analyze` → No issues

### Step 4: Add revoke to ShareNoteController

Modify `lib/features/notes/presentation/controllers/share_note_controller.dart` to add a `revoke` method that calls `deleteShare`.

```dart
  Future<void> revoke({
    required String noteId,
    required String userId,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(sharesRepositoryProvider).deleteShare(
            noteId: noteId,
            userId: userId,
          ),
    );
  }
```

**Verify**: `flutter analyze` → No issues

### Step 5: Refactor ShareListSection

Modify `lib/features/notes/presentation/widgets/share_list_section.dart` to:
1. Use `ListView.separated` instead of a manual `for` loop with `Divider`.
2. Import `../controllers/share_note_controller.dart` and call `revoke` instead of `sharesRepositoryProvider`.
3. Simplify the error messages and loading states.

**Verify**: `flutter analyze` → No issues

### Step 6: Refactor ShareNoteSheet

Modify `lib/features/notes/presentation/widgets/share_note_sheet.dart` to:
1. Use `AppInput` instead of `TextField`.
2. Use `DropdownButtonHideUnderline` or standard `InputDecorator` cleanly.
3. Remove simple strings from `NoteStrings` and inline them.

**Verify**: `flutter analyze` → No issues

## Test plan

- Test compilation: `flutter analyze` must pass with 0 errors.
- Manual test plan: Open the app, create a task in a note, tap on the badges to edit the task metadata (due date and recurrence), and ensure the UI saves. Open a note, click Share, add an email as an Editor, and revoke their access.

## Done criteria

Machine-checkable. ALL must hold:
- [ ] `flutter analyze` exits 0.
- [ ] `lib/features/tasks/presentation/widgets/task_edit_sheet.dart` is deleted.
- [ ] No manual `tasksRepositoryProvider` or `sharesRepositoryProvider` injections remain in the UI sheets.

## STOP conditions

Stop and report back (do not improvise) if:
- `flutter analyze` fails to pass after applying a step.

## Maintenance notes

- `TaskController` and `ShareNoteController` now handle the mutations. Ensure future UI screens for tasks or sharing use these controllers instead of directly reading repositories.

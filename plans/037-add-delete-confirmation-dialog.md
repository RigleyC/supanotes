# Plan 037: Add confirmation dialog before deleting recurring tasks

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 34998f2..HEAD -- lib/features/tasks/presentation/widgets/task_edit_sheet.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: UX
- **Planned at**: commit `34998f2`, 2026-06-18

## Why this matters

The "Excluir" button in `TaskEditSheet` deletes the task immediately with no confirmation. For a non-recurring task this is acceptable, but for a recurring task the user is destroying a repeating schedule they may have relied on. A confirmation dialog — with a different message for recurring tasks — prevents accidental data loss.

## Current state

- File: `lib/features/tasks/presentation/widgets/task_edit_sheet.dart`
- Method: `_onDelete()` (lines 145–159)

Current code:

```dart
Future<void> _onDelete() async {
  final task = widget.task;
  if (task == null) return;
  setState(() => _saving = true);
  final repo = ref.read(tasksRepositoryProvider);
  final navigator = Navigator.of(context);
  try {
    await repo.deleteTask(task.id);
    navigator.pop(TaskEditResult(task: task, deleted: true));
  } catch (e) {
    if (!mounted) return;
    AppMessenger.showError(context, 'Erro ao excluir tarefa: $e');
    setState(() => _saving = false);
  }
}
```

The `task` is available as `widget.task` (a `TaskModel?`). It has `recurrence` field (`TaskRecurrence?`).

## Commands you will need

| Purpose   | Command                              | Expected on success    |
|-----------|--------------------------------------|------------------------|
| Analyze   | `dart analyze lib/features/tasks/presentation/widgets/task_edit_sheet.dart` | No issues found |

## Scope

**In scope**:
- `lib/features/tasks/presentation/widgets/task_edit_sheet.dart` (only `_onDelete` method)

**Out of scope**:
- Task deletion from the note editor (different path, `allowDelete: false`)
- Task deletion via swipe in `TaskTile` (handled by caller)
- Backend delete logic

## Steps

### Step 1: Add confirmation dialog to `_onDelete`

Replace the `_onDelete` method with one that shows a confirmation dialog first. Use `showDialog` with `AlertDialog`.

The dialog message should differentiate:
- Recurring task: "Tem certeza que deseja excluir esta tarefa recorrente? Ela não será mais reagendada."
- Non-recurring task: "Tem certeza que deseja excluir esta tarefa?"

```dart
Future<void> _onDelete() async {
  final task = widget.task;
  if (task == null) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Excluir tarefa'),
      content: Text(
        task.recurrence != null
            ? 'Tem certeza que deseja excluir esta tarefa recorrente? Ela não será mais reagendada.'
            : 'Tem certeza que deseja excluir esta tarefa?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Excluir'),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  setState(() => _saving = true);
  final repo = ref.read(tasksRepositoryProvider);
  final navigator = Navigator.of(context);
  try {
    await repo.deleteTask(task.id);
    navigator.pop(TaskEditResult(task: task, deleted: true));
  } catch (e) {
    if (!mounted) return;
    AppMessenger.showError(context, 'Erro ao excluir tarefa: $e');
    setState(() => _saving = false);
  }
}
```

### Step 2: Verify

**Verify**: `dart analyze lib/features/tasks/presentation/widgets/task_edit_sheet.dart` → No issues found

## Test plan

No new tests required — this is a UI-only change with no logic to unit test. The dialog is a standard Flutter `showDialog` pattern.

## Done criteria

- [ ] `dart analyze lib/features/tasks/presentation/widgets/task_edit_sheet.dart` exits 0
- [ ] `_onDelete` shows a confirmation dialog before deleting
- [ ] Dialog message mentions "recorrente" when `task.recurrence != null`
- [ ] Dialog has "Cancelar" and "Excluir" buttons
- [ ] No files outside scope modified

## STOP conditions

- The code at lines 145–159 doesn't match the "Current state" excerpt.
- A step's verification fails twice.
- The fix requires touching files outside `task_edit_sheet.dart`.

## Maintenance notes

- The same pattern could be applied to `TaskTile`'s swipe-to-delete if desired in the future.
- The dialog uses `TextButton` for both actions, matching the existing Material dialog pattern in the app.

# Plan 040: Fix TaskDateFilter.overdue to exclude completed tasks

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 34998f2..HEAD -- lib/features/tasks/domain/task_date_filter.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: correctness
- **Planned at**: commit `34998f2`, 2026-06-18

## Why this matters

`TaskDateFilter.overdue` filters tasks where `dueDate` is before today, but does not check `isCompleted`. It currently works by coincidence because the upstream stream (`watchOpenTasks`) only provides open tasks. But the filter's semantics should match `TaskModel.isOverdue` (which does check `isCompleted`) for defensive programming. If the filter is ever reused with a different stream, it would incorrectly include completed tasks.

## Current state

- File: `lib/features/tasks/domain/task_date_filter.dart`
- Method: `overdue()` (lines 5–10)

Current code:

```dart
static List<TaskModel> overdue(List<TaskModel> tasks, {required DateTime today}) {
  return tasks
      .where((t) => t.dueDate != null && !t.dueDate!.isSameDayAs(today) && t.dueDate!.isBefore(today))
      .toList()
    ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
}
```

Compare with `TaskModel.isOverdue` (in `task_model.dart`):
```dart
bool get isOverdue => !isCompleted && dueDate != null && !dueDate!.isSameDayAs(DateTime.now()) && dueDate!.isBefore(DateTime.now());
```

## Commands you will need

| Purpose   | Command                              | Expected on success    |
|-----------|--------------------------------------|------------------------|
| Analyze   | `dart analyze lib/features/tasks/domain/task_date_filter.dart` | No issues found |
| Test      | `flutter test test/features/tasks/domain/task_date_filter_test.dart` | All pass |

## Scope

**In scope**:
- `lib/features/tasks/domain/task_date_filter.dart` (only `overdue` method)

**Out of scope**:
- `TaskModel.isOverdue` — already correct
- Other filter methods
- UI changes

## Steps

### Step 1: Add `!t.isCompleted` to the filter

```dart
static List<TaskModel> overdue(List<TaskModel> tasks, {required DateTime today}) {
  return tasks
      .where((t) => !t.isCompleted && t.dueDate != null && !t.dueDate!.isSameDayAs(today) && t.dueDate!.isBefore(today))
      .toList()
    ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
}
```

### Step 2: Verify

**Verify**: `dart analyze lib/features/tasks/domain/task_date_filter.dart` → No issues found
**Verify**: `flutter test test/features/tasks/domain/task_date_filter_test.dart` → All pass

## Test plan

Existing tests should pass. The new condition is only triggered when a completed task is passed to the filter, which the existing tests don't do.

## Done criteria

- [ ] `dart analyze lib/features/tasks/domain/task_date_filter.dart` exits 0
- [ ] `flutter test test/features/tasks/domain/task_date_filter_test.dart` exits 0
- [ ] `overdue()` includes `!t.isCompleted` in the filter predicate
- [ ] No files outside scope modified

## STOP conditions

- The code at lines 5–10 doesn't match the "Current state" excerpt.
- A step's verification fails twice.

## Maintenance notes

- This is a defensive change. The current callers already filter completed tasks upstream, so this is a no-op in practice but prevents future bugs.

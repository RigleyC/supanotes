# Plan 039: Couple recurrence picker with due date selection

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

- **Priority**: P3
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: UX
- **Planned at**: commit `34998f2`, 2026-06-18

## Why this matters

The `DueDatePicker` and `RecurrencePicker` are completely independent. A user can set "Weekly" recurrence with no due date. While the backend handles this gracefully (falling back to `DateTime.now()` in `completeTask`), the user has no indication that their recurring task has no anchor date. The recurrence anchor shifts every time the task is completed, which is confusing.

The fix: when the user selects a recurrence and no due date is set, auto-set the due date to today. This gives the recurrence a stable anchor.

## Current state

- File: `lib/features/tasks/presentation/widgets/task_edit_sheet.dart`
- State: `_dueDate` (line 68), `_recurrence` (line 69)
- `RecurrencePicker.onChanged` (line 204): `onChanged: (r) => setState(() => _recurrence = r)`

The two pickers are independent — neither knows about the other.

## Commands you will need

| Purpose   | Command                              | Expected on success    |
|-----------|--------------------------------------|------------------------|
| Analyze   | `dart analyze lib/features/tasks/presentation/widgets/task_edit_sheet.dart` | No issues found |

## Scope

**In scope**:
- `lib/features/tasks/presentation/widgets/task_edit_sheet.dart` (only the `RecurrencePicker.onChanged` callback)

**Out of scope**:
- `DueDatePicker` widget changes
- `RecurrencePicker` widget changes
- Backend logic

## Steps

### Step 1: Auto-set due date when recurrence is chosen

Change the `RecurrencePicker.onChanged` callback to also set `_dueDate` to today if it's currently null:

```dart
RecurrencePicker(
  initialRecurrence: _recurrence,
  onChanged: (r) => setState(() {
    _recurrence = r;
    // Anchor the recurrence to today if no due date is set.
    if (r != null && _dueDate == null) {
      _dueDate = DateTime.now().startOfDay;
    }
  }),
),
```

This requires importing `date_time_extensions.dart` for the `startOfDay` getter. Check if it's already imported — if not, add:

```dart
import 'package:supanotes/core/utils/date_time_extensions.dart';
```

### Step 2: Verify

**Verify**: `dart analyze lib/features/tasks/presentation/widgets/task_edit_sheet.dart` → No issues found

## Test plan

No new tests required — this is a UX convenience behavior.

## Done criteria

- [ ] `dart analyze lib/features/tasks/presentation/widgets/task_edit_sheet.dart` exits 0
- [ ] When user selects a recurrence and `_dueDate` is null, `_dueDate` is set to today's start of day
- [ ] When user selects a recurrence and `_dueDate` is already set, it stays unchanged
- [ ] When user selects "Nenhuma" (null recurrence), `_dueDate` is not affected
- [ ] No files outside scope modified

## STOP conditions

- The code at lines 202–205 doesn't match the "Current state" excerpt.
- A step's verification fails twice.
- The fix requires touching files outside `task_edit_sheet.dart`.

## Maintenance notes

- This is a one-way coupling: selecting recurrence auto-sets due date, but clearing due date does NOT clear recurrence. This is intentional — the user might want to keep the recurrence but change the anchor manually later.
- If the UX team later wants a warning instead of auto-set, the callback can be changed to show an info snackbar instead.

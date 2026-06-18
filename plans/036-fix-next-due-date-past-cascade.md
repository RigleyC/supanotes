# Plan 036: Fix `_nextDueDate` past-date cascade for recurring tasks

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 34998f2..HEAD -- lib/core/database/daos/tasks_dao.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `34998f2`, 2026-06-18

## Why this matters

When a recurring task's `dueDate` is in the past (e.g., user forgot to complete it for 3 days), `_nextDueDate` computes `pastDate + interval`, which may still be in the past. A daily task due 3 days ago gets `dueDate = 2 days ago` — immediately overdue again. This creates a cascade of overdue tasks that never resolves.

The fix: after computing the next date, if it's still before today, fast-forward to today (or today + interval for daily).

## Current state

- File: `lib/core/database/daos/tasks_dao.dart`
- Function: `_nextDueDate()` (lines 236–265)
- Called from: `completeTask()` at line 134

Current code:

```dart
DateTime? _nextDueDate({
  required DateTime from,
  required TaskRecurrence recurrence,
}) {
  switch (recurrence) {
    case TaskRecurrence.daily:
      return from.add(const Duration(days: 1));
    case TaskRecurrence.weekdays:
      var day = from.add(const Duration(days: 1));
      while (day.weekday == DateTime.saturday ||
          day.weekday == DateTime.sunday) {
        day = day.add(const Duration(days: 1));
      }
      return day;
    case TaskRecurrence.weekly:
      return from.add(const Duration(days: 7));
    case TaskRecurrence.monthly:
      final desiredMonth = from.month + 1;
      final overflow = desiredMonth > 12;
      final year = from.year + (overflow ? 1 : 0);
      final month = overflow ? 1 : desiredMonth;
      final lastDayOfTarget = DateTime(year, month + 1, 0).day;
      final day = from.day <= lastDayOfTarget ? from.day : lastDayOfTarget;
      return DateTime(year, month, day);
  }
}
```

The `from` parameter comes from `task.dueDate ?? now` (line 135). If `dueDate` is 3 days ago, `from` is 3 days ago, and `daily` returns 2 days ago.

## Commands you will need

| Purpose   | Command                              | Expected on success    |
|-----------|--------------------------------------|------------------------|
| Analyze   | `dart analyze lib/core/database/daos/tasks_dao.dart` | No issues found |
| Test      | `flutter test test/core/database/daos/tasks_dao_test.dart` | All pass |

## Scope

**In scope**:
- `lib/core/database/daos/tasks_dao.dart` (only `_nextDueDate` function and `completeTask` where it's called)

**Out of scope**:
- Backend `calculateNextDueDate()` — separate codebase, same logic but different file
- UI changes
- Other DAO methods

## Steps

### Step 1: Add fast-forward logic to `_nextDueDate`

After computing the next date in each case, check if it's before today. If so, advance it to today (for daily/weekdays) or today + interval (for weekly/monthly).

The cleanest approach: add a helper at the top of the function that normalizes the result.

```dart
DateTime? _nextDueDate({
  required DateTime from,
  required TaskRecurrence recurrence,
}) {
  final today = DateTime.now();
  final todayStart = DateTime(today.year, today.month, today.day);

  DateTime? raw;
  switch (recurrence) {
    case TaskRecurrence.daily:
      raw = from.add(const Duration(days: 1));
    case TaskRecurrence.weekdays:
      var day = from.add(const Duration(days: 1));
      while (day.weekday == DateTime.saturday ||
          day.weekday == DateTime.sunday) {
        day = day.add(const Duration(days: 1));
      }
      raw = day;
    case TaskRecurrence.weekly:
      raw = from.add(const Duration(days: 7));
    case TaskRecurrence.monthly:
      final desiredMonth = from.month + 1;
      final overflow = desiredMonth > 12;
      final year = from.year + (overflow ? 1 : 0);
      final month = overflow ? 1 : desiredMonth;
      final lastDayOfTarget = DateTime(year, month + 1, 0).day;
      final day = from.day <= lastDayOfTarget ? from.day : lastDayOfTarget;
      raw = DateTime(year, month, day);
  }

  // If the computed date is still in the past, fast-forward to today.
  if (raw != null && raw.isBefore(todayStart)) {
    raw = todayStart;
  }

  return raw;
}
```

### Step 2: Verify

**Verify**: `dart analyze lib/core/database/daos/tasks_dao.dart` → No issues found
**Verify**: `flutter test test/core/database/daos/tasks_dao_test.dart` → All pass

## Test plan

Existing tests should still pass. The new behavior (fast-forward to today) is only triggered when `from` is in the past, which none of the existing tests exercise.

To verify the fix manually: the existing test "completing a recurring task without due date uses today" should still pass (line 75–112 of tasks_dao_test.dart) — it uses `DateTime.now()` which is today, so the fast-forward doesn't trigger.

## Done criteria

- [ ] `dart analyze lib/core/database/daos/tasks_dao.dart` exits 0
- [ ] `flutter test test/core/database/daos/tasks_dao_test.dart` exits 0
- [ ] `_nextDueDate` returns a date not before today's start when the computed result would be in the past
- [ ] No files outside scope modified

## STOP conditions

- The code at lines 236–265 doesn't match the "Current state" excerpt.
- A step's verification fails twice.
- The fix requires touching files outside `lib/core/database/daos/tasks_dao.dart`.

## Maintenance notes

- If the backend `calculateNextDueDate()` in `backend/internal/tasks/service.go` is ever synced with this logic, it needs the same fast-forward.
- The fast-forward uses local midnight, matching how `watchTodayTasks` filters.

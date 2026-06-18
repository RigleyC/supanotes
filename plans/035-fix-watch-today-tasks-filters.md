# Plan 035: Fix `watchTodayTasks` missing filters

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
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `34998f2`, 2026-06-18

## Why this matters

`watchTodayTasks` is the query behind the "Hoje" screen. It has two bugs:
1. It does not filter out soft-deleted tasks (`deletedAt`), so deleted recurring tasks can ghost back into the today view before sync runs.
2. It uses hardcoded `23:59:59` as the upper bound instead of start-of-next-day with `<`, which is semantically incorrect (excludes sub-second precision and would break if storage precision changes).

Both are one-line fixes in the same query.

## Current state

- File: `lib/core/database/daos/tasks_dao.dart`
- Method: `watchTodayTasks()` (lines 19–36)

Current code:

```dart
Stream<List<TaskData>> watchTodayTasks() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  return (select(tasks)
        ..where((t) => t.dueDate.isSmallerOrEqualValue(
            DateTime(today.year, today.month, today.day, 23, 59, 59)))
        ..orderBy([
          (t) => OrderingTerm(
                expression: t.status.equals('done'),
                mode: OrderingMode.asc,
              ),
          (t) => OrderingTerm(expression: t.dueDate, mode: OrderingMode.asc),
          (t) =>
              OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
        ]))
      .watch();
}
```

Compare with `watchOpenTasks` (line 42–53) which correctly filters `t.deletedAt.isNull()`.

## Commands you will need

| Purpose   | Command                              | Expected on success    |
|-----------|--------------------------------------|------------------------|
| Analyze   | `dart analyze lib/core/database/daos/tasks_dao.dart` | No issues found |
| Test      | `flutter test test/core/database/daos/tasks_dao_test.dart` | All pass |

## Scope

**In scope**:
- `lib/core/database/daos/tasks_dao.dart` (only `watchTodayTasks` method)

**Out of scope**:
- `watchOpenTasks`, `watchNoteTasks` — unchanged
- Any other DAO methods
- Backend queries

## Steps

### Step 1: Add `deletedAt.isNull()` filter

Add a `where` clause for soft-delete, matching the pattern in `watchOpenTasks`:

```dart
..where((t) => t.deletedAt.isNull())
```

Insert it after the existing `dueDate` filter (before `..orderBy`).

### Step 2: Replace `23:59:59` with start-of-next-day

Replace:
```dart
..where((t) => t.dueDate.isSmallerOrEqualValue(
    DateTime(today.year, today.month, today.day, 23, 59, 59)))
```

With:
```dart
..where((t) => t.dueDate.isSmallerThan(today.add(const Duration(days: 1))))
```

This uses `<` (via `isSmallerThan`) instead of `<=` with a hardcoded time, which is the correct semantic for "before end of today."

### Step 3: Verify

**Verify**: `dart analyze lib/core/database/daos/tasks_dao.dart` → No issues found
**Verify**: `flutter test test/core/database/daos/tasks_dao_test.dart` → All pass

## Test plan

The existing `tasks_dao_test.dart` tests should continue to pass. No new tests are required for this plan since the query changes are backward-compatible — the same tasks appear in the today view, minus soft-deleted ones.

## Done criteria

- [ ] `dart analyze lib/core/database/daos/tasks_dao.dart` exits 0
- [ ] `flutter test test/core/database/daos/tasks_dao_test.dart` exits 0
- [ ] `watchTodayTasks` includes `deletedAt.isNull()` filter
- [ ] `watchTodayTasks` uses `isSmallerThan` with `today.add(Duration(days: 1))` instead of `23:59:59`
- [ ] No files outside scope modified (`git status`)

## STOP conditions

- The code at lines 19–36 doesn't match the "Current state" excerpt (codebase drifted).
- A step's verification fails twice after a reasonable fix attempt.
- The fix requires touching files outside `lib/core/database/daos/tasks_dao.dart`.

## Maintenance notes

- If a new query method is added for "today" tasks, it should follow the same pattern: `deletedAt.isNull()` + `isSmallerThan(today.add(Duration(days: 1)))`.
- The `dueDate` column stores local DateTime. The filter works correctly because `today` is already local midnight.

# Plan 041: Make TaskMetadataBadges testable and fix recurrenceLabel

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 34998f2..HEAD -- lib/features/tasks/presentation/widgets/task_metadata_badges.dart lib/features/tasks/presentation/widgets/recurrence_picker.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit `34998f2`, 2026-06-18

## Why this matters

Two small issues:

1. `TaskMetadataBadges._dueDateLabel` and `_dueDateColor` call `DateTime.now()` directly in `build()`. This makes the widget non-deterministic and hard to test — snapshot tests break across midnight, and the behavior depends on when `build()` runs.

2. `recurrenceLabel()` returns an empty string for `null` (line 70 of `recurrence_picker.dart`). This is a code smell — the function should never be called with `null` since the badge is only shown when `_hasRecurrence` is true.

## Current state

- File: `lib/features/tasks/presentation/widgets/task_metadata_badges.dart`
  - `_dueDateLabel` (lines 55–67): calls `DateTime.now().startOfDay` at line 56
  - `_dueDateColor` (lines 69–80): calls `DateTime.now().startOfDay` at line 74
- File: `lib/features/tasks/presentation/widgets/recurrence_picker.dart`
  - `recurrenceLabel` (lines 59–72): `default: return '';` at line 70

## Commands you will need

| Purpose   | Command                              | Expected on success    |
|-----------|--------------------------------------|------------------------|
| Analyze   | `dart analyze lib/features/tasks/presentation/widgets/task_metadata_badges.dart lib/features/tasks/presentation/widgets/recurrence_picker.dart` | No issues found |
| Test      | `flutter test test/features/tasks/presentation/widgets/task_metadata_badges_test.dart` | All pass |

## Scope

**In scope**:
- `lib/features/tasks/presentation/widgets/task_metadata_badges.dart`
- `lib/features/tasks/presentation/widgets/recurrence_picker.dart`

**Out of scope**:
- `TaskTile` — caller of `TaskMetadataBadges`
- `CustomTaskComponent` — caller of `TaskMetadataBadges`
- Other badge tests

## Steps

### Step 1: Add `now` parameter to TaskMetadataBadges

Add an optional `now` parameter that defaults to `DateTime.now()`. Use it in `_dueDateLabel` and `_dueDateColor` instead of calling `DateTime.now()` directly:

```dart
class TaskMetadataBadges extends StatelessWidget {
  const TaskMetadataBadges({
    super.key,
    this.dueDate,
    this.recurrence,
    this.isCompleted = false,
    this.now,
  });

  final DateTime? dueDate;
  final TaskRecurrence? recurrence;
  final bool isCompleted;
  final DateTime? now;
```

Then in `_dueDateLabel` and `_dueDateColor`, replace `DateTime.now().startOfDay` with `(now ?? DateTime.now()).startOfDay`.

### Step 2: Make recurrenceLabel non-nullable

Change the `default` case in `recurrenceLabel` to throw instead of returning empty string:

```dart
String recurrenceLabel(TaskRecurrence? recurrence) {
  switch (recurrence) {
    case TaskRecurrence.daily:
      return 'Diariamente';
    case TaskRecurrence.weekdays:
      return 'Dias úteis';
    case TaskRecurrence.weekly:
      return 'Semanalmente';
    case TaskRecurrence.monthly:
      return 'Mensalmente';
    case null:
      return '';
  }
}
```

Actually, keeping `null` case returning `''` is fine since the caller already guards with `_hasRecurrence`. But changing from `default` to explicit `case null:` makes the switch exhaustive and documents the intent.

### Step 3: Verify

**Verify**: `dart analyze lib/features/tasks/presentation/widgets/task_metadata_badges.dart lib/features/tasks/presentation/widgets/recurrence_picker.dart` → No issues found
**Verify**: `flutter test test/features/tasks/presentation/widgets/task_metadata_badges_test.dart` → All pass

## Test plan

Existing tests should pass. The new `now` parameter is optional and defaults to the current behavior.

## Done criteria

- [ ] `dart analyze` exits 0 for both files
- [ ] `flutter test test/features/tasks/presentation/widgets/task_metadata_badges_test.dart` exits 0
- [ ] `TaskMetadataBadges` has an optional `now` parameter
- [ ] `_dueDateLabel` and `_dueDateColor` use `(now ?? DateTime.now()).startOfDay` instead of `DateTime.now().startOfDay`
- [ ] `recurrenceLabel` uses explicit `case null:` instead of `default:`
- [ ] No files outside scope modified

## STOP conditions

- The code doesn't match the "Current state" excerpts.
- A step's verification fails twice.

## Maintenance notes

- The `now` parameter is primarily for testability. Callers don't need to pass it — the default behavior is unchanged.
- Future tests can pass a fixed `now` to test "today", "overdue", and "future" badge states deterministically.

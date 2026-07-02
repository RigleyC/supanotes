# Plan 002: Refactor Date and Recurrence Pickers to Extract Domain Logic

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat d9ddf89..HEAD -- lib/features/tasks/presentation/widgets/due_date_picker.dart lib/features/tasks/presentation/widgets/recurrence_picker.dart lib/features/tasks/presentation/widgets/task_metadata_badges.dart lib/features/tasks/domain/task_recurrence.dart lib/core/utils/date_time_extensions.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit `d9ddf89`, 2026-07-02

## Why this matters

The `DueDatePicker` currently defines heavy business logic (date constraints, `isQuickPick` verification) right inside its `build()` method, which re-evaluates unnecessarily and pollutes the UI layer. Furthermore, it uses "Next Monday" instead of the standard "Next Week" (7 days). 
Meanwhile, the `RecurrencePicker` contains loose UI models (`_RecurrenceOption`) and free-floating functions (`recurrenceLabel`) inside the UI file instead of utilizing standard Dart `extension` methods on the `TaskRecurrence` enum itself. Extricating this logic makes the UI components cleaner, leaner, and globally reusable across the app (like in `TaskMetadataBadges`).

## Current state

- `lib/features/tasks/presentation/widgets/due_date_picker.dart` — Defines local variables inside `build`:
  ```dart
  // file:27-30
      final now = DateTime.now();
      final today = now.startOfDay;
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final nextMonday = today.add(Duration(days: 8 - today.weekday));
  ```
- `lib/features/tasks/presentation/widgets/recurrence_picker.dart` — Defines UI maps outside the class:
  ```dart
  // file:16-17
    static const _options = <_RecurrenceOption>[
      _RecurrenceOption(value: null, label: 'Nenhuma', icon: Icons.do_not_disturb_on_outlined),
  ```
  And a free-floating formatting method:
  ```dart
  // file:51-53
  String recurrenceLabel(TaskRecurrence? recurrence) {
    switch (recurrence) {
      case TaskRecurrence.daily:
  ```
- `lib/features/tasks/presentation/widgets/task_metadata_badges.dart` — Relies on the loose `recurrenceLabel`:
  ```dart
  // file:49-51
            icon: Icons.refresh,
            label: recurrenceLabel(recurrence),
            color: scheme.onSurfaceVariant,
  ```
- `lib/features/tasks/domain/task_recurrence.dart` — Just the bare enum.
- `lib/core/utils/date_time_extensions.dart` — Just `isSameDayAs` and `startOfDay`.
- **Testing context**: There are no automated widget tests covering the task flows in `test/features/tasks/`. Thus, there is no verification suite via `flutter test`. We rely purely on type safety (`flutter analyze`) and manual verification.

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Typecheck | `flutter analyze`        | exit 0, no issues   |

## Scope

**In scope**:
- `lib/features/tasks/domain/task_recurrence.dart`
- `lib/features/tasks/presentation/widgets/recurrence_picker.dart`
- `lib/features/tasks/presentation/widgets/task_metadata_badges.dart`
- `lib/core/utils/date_time_extensions.dart`
- `lib/features/tasks/presentation/widgets/due_date_picker.dart`

**Out of scope**:
- Unrelated picker features or state management providers.
- Writing new widget tests (no test baseline exists).

## Git workflow

- Commit per step or per logical unit. Message style: conventional commits (e.g., `refactor(tasks): extract recurrence UI metadata to enum extension`).

## Steps

### Step 1: Add extensions to TaskRecurrence

Modify `lib/features/tasks/domain/task_recurrence.dart`.
Add `import 'package:flutter/material.dart';` and create an extension on `TaskRecurrence` to provide `label` and `icon`.

```dart
import 'package:flutter/material.dart';

enum TaskRecurrence {
  daily,
  weekdays,
  weekly,
  monthly;

  static TaskRecurrence? parse(String? value) {
    if (value == null) return null;
    for (final e in TaskRecurrence.values) {
      if (e.name == value) return e;
    }
    return null;
  }
}

extension TaskRecurrenceUI on TaskRecurrence {
  String get label {
    switch (this) {
      case TaskRecurrence.daily:
        return 'Diariamente';
      case TaskRecurrence.weekdays:
        return 'Dias úteis';
      case TaskRecurrence.weekly:
        return 'Semanalmente';
      case TaskRecurrence.monthly:
        return 'Mensalmente';
    }
  }

  IconData get icon {
    switch (this) {
      case TaskRecurrence.daily:
        return Icons.today_rounded;
      case TaskRecurrence.weekdays:
        return Icons.work_outline;
      case TaskRecurrence.weekly:
        return Icons.calendar_view_week_outlined;
      case TaskRecurrence.monthly:
        return Icons.calendar_month_outlined;
    }
  }
}
```

**Verify**: `flutter analyze` → No issues

### Step 2: Refactor RecurrencePicker and TaskMetadataBadges

Modify `lib/features/tasks/presentation/widgets/recurrence_picker.dart`.
Delete the `_options` array, `_RecurrenceOption` class, and `recurrenceLabel` top-level function. Instead, map over `TaskRecurrence.values` directly, and manually prepend the "Nenhuma" option.

```dart
import 'package:flutter/material.dart';
import 'package:supanotes/shared/widgets/app_selection_tile.dart';
import '../../domain/task_recurrence.dart';

class RecurrencePicker extends StatelessWidget {
  const RecurrencePicker({
    super.key,
    required this.initialRecurrence,
    required this.onChanged,
  });

  final TaskRecurrence? initialRecurrence;
  final ValueChanged<TaskRecurrence?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppSelectionTile(
            label: 'Nenhuma',
            icon: Icons.do_not_disturb_on_outlined,
            isSelected: initialRecurrence == null,
            onTap: () => onChanged(null),
          ),
        ),
        for (final option in TaskRecurrence.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppSelectionTile(
              label: option.label,
              icon: option.icon,
              isSelected: option == initialRecurrence,
              onTap: () => onChanged(option),
            ),
          ),
      ],
    );
  }
}
```

Modify `lib/features/tasks/presentation/widgets/task_metadata_badges.dart` line 50. Replace `recurrenceLabel(recurrence)` with `recurrence!.label`.

**Verify**: `flutter analyze` → No issues

### Step 3: Add extension method for DueDatePicker

Modify `lib/core/utils/date_time_extensions.dart`. Add an `isQuickPick()` method to evaluate if a date is one of the shortcut dates (today, tomorrow, or next week). Note: We define "next week" as exactly 7 days from today.

```dart
extension DateTimeDateOnly on DateTime {
  /// Returns `true` if this DateTime represents the same calendar day as [other].
  bool isSameDayAs(DateTime other) {
    return year == other.year && month == other.month && day == other.day;
  }

  /// Returns a new DateTime with the time zeroed out.
  DateTime get startOfDay {
    return DateTime(year, month, day);
  }

  /// Returns true if this date matches 'Today', 'Tomorrow', or 'Next Week'
  bool isQuickPick() {
    final today = DateTime.now().startOfDay;
    final tomorrow = today.add(const Duration(days: 1));
    final nextWeek = today.add(const Duration(days: 7));
    
    return isSameDayAs(today) || isSameDayAs(tomorrow) || isSameDayAs(nextWeek);
  }
}
```

**Verify**: `flutter analyze` → No issues

### Step 4: Refactor DueDatePicker

Modify `lib/features/tasks/presentation/widgets/due_date_picker.dart`.
Remove variables from `build()`. Remove `_isQuickPick` function. Update "Próx. segunda" to "Próxima semana" (today + 7 days).

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supanotes/core/utils/date_time_extensions.dart';
import 'package:supanotes/shared/widgets/app_selection_tile.dart';

class DueDatePicker extends StatefulWidget {
  const DueDatePicker({
    super.key,
    required this.initialDate,
    required this.onChanged,
  });

  final DateTime? initialDate;
  final ValueChanged<DateTime?> onChanged;

  @override
  State<DueDatePicker> createState() => _DueDatePickerState();
}

class _DueDatePickerState extends State<DueDatePicker> {
  bool _isCalendarExpanded = false;

  bool _isSelected(DateTime value) {
    if (widget.initialDate == null) return false;
    return value.isSameDayAs(widget.initialDate!);
  }

  bool _isCustomDate() {
    if (widget.initialDate == null) return false;
    return !widget.initialDate!.isQuickPick();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = now.startOfDay;
    final tomorrow = today.add(const Duration(days: 1));
    final nextWeek = today.add(const Duration(days: 7));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSelectionTile(
          label: 'Hoje',
          icon: Icons.calendar_month_rounded,
          isSelected: _isSelected(today),
          onTap: () {
            setState(() => _isCalendarExpanded = false);
            widget.onChanged(today);
          },
        ),
        AppSelectionTile(
          label: 'Amanhã',
          icon: Icons.calendar_month_rounded,
          isSelected: _isSelected(tomorrow),
          onTap: () {
            setState(() => _isCalendarExpanded = false);
            widget.onChanged(tomorrow);
          },
        ),
        AppSelectionTile(
          label: 'Próxima semana',
          icon: Icons.calendar_month_rounded,
          isSelected: _isSelected(nextWeek),
          onTap: () {
            setState(() => _isCalendarExpanded = false);
            widget.onChanged(nextWeek);
          },
        ),
        AppSelectionTile(
          label: _isCustomDate()
              ? DateFormat('d MMM').format(widget.initialDate!)
              : 'Escolher data',
          icon: Icons.calendar_month_rounded,
          isSelected: _isCustomDate(),
          onTap: () {
            setState(() => _isCalendarExpanded = !_isCalendarExpanded);
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _isCalendarExpanded
              ? ClipRect(
                  child: CalendarDatePicker(
                    initialDate: widget.initialDate ?? today,
                    firstDate: DateTime(now.year - 1),
                    lastDate: DateTime(now.year + 5),
                    onDateChanged: (date) {
                      setState(() => _isCalendarExpanded = false);
                      widget.onChanged(date);
                    },
                  ),
                )
              : const SizedBox.shrink(),
        ),
        AppSelectionTile(
          label: 'Sem data',
          icon: Icons.block,
          isSelected: widget.initialDate == null,
          onTap: () {
            setState(() => _isCalendarExpanded = false);
            widget.onChanged(null);
          },
        ),
      ],
    );
  }
}
```

**Verify**: `flutter analyze` → No issues

## Test plan

- Test compilation: `flutter analyze` must pass with 0 errors.
- Manual test plan: Open the app, create a task, open the TaskMetadataSheet, tap "Hoje", "Amanhã", and "Próxima semana". Verify they set the correct dates. Tap "Escolher data" and verify the native calendar expands smoothly. Verify recurrence options show correctly and are clickable. Note: no automated widget tests exist for this component.

## Done criteria

Machine-checkable. ALL must hold:
- [ ] `flutter analyze` exits 0.
- [ ] `TaskRecurrenceUI` extension exists in `lib/features/tasks/domain/task_recurrence.dart`.
- [ ] `_RecurrenceOption` and `recurrenceLabel` are deleted from `recurrence_picker.dart`.
- [ ] `_isQuickPick` function is removed from `due_date_picker.dart` and implemented as an extension on `DateTime`.

## STOP conditions

Stop and report back (do not improvise) if:
- `flutter analyze` fails to pass after applying a step.
- The `recurrenceLabel` function is referenced by any out-of-scope files (e.g., any file other than `task_metadata_badges.dart` and `recurrence_picker.dart` that wasn't included in this plan).
- The existing `_isQuickPick` logic in `due_date_picker.dart` contains conditions other than today, tomorrow, or next Monday, which would indicate drift.

## Maintenance notes

- Future additions to `TaskRecurrence` enum should also add cases to the `TaskRecurrenceUI` extension.

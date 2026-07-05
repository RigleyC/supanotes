# Plan 001: Implement Dynamic Task Recurrence Labels

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat d11728e..HEAD -- lib/features/tasks/domain/task_recurrence.dart lib/features/tasks/presentation/widgets/recurrence_picker.dart lib/features/tasks/presentation/widgets/task_metadata_sheet.dart lib/features/tasks/presentation/widgets/task_metadata_badges.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: feature
- **Planned at**: commit `d11728e`, 2026-07-04

## Why this matters

Currently, the task recurrence options in the bottom-sheet always display static labels ("Semanalmente", "Mensalmente") regardless of the selected due date. For weekly and monthly recurrences, it is much clearer to display the specific day of the repetition (e.g. "Semanalmente (quinta-feira)" or "Mensalmente (dia 15)"). This helps the user verify exactly which repetition pattern they are scheduling before saving the task.

## Current state

The following files are in scope for modification:
- `lib/features/tasks/domain/task_recurrence.dart` — holds the `TaskRecurrence` enum and `TaskRecurrenceUI` extension.
- `lib/features/tasks/presentation/widgets/recurrence_picker.dart` — widget displaying the list of recurrence options.
- `lib/features/tasks/presentation/widgets/task_metadata_sheet.dart` — bottom sheet containing date and recurrence pickers.
- `lib/features/tasks/presentation/widgets/task_metadata_badges.dart` — widget displaying task metadata pill/badges under the task text.
- `test/features/tasks/presentation/widgets/task_metadata_sheet_test.dart` — tests for the metadata sheet.
- `test/features/tasks/presentation/widgets/task_metadata_badges_test.dart` — tests for the task metadata badges.
- `test/features/tasks/presentation/widgets/task_tile_test.dart` — tests for the task tiles.

### Existing Code Excerpts

In [task_recurrence.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/tasks/domain/task_recurrence.dart):
```dart
extension TaskRecurrenceUI on TaskRecurrence {
  String get label {
    switch (this) {
      case TaskRecurrence.daily:
        return 'Diariamente';
...
```

In [recurrence_picker.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/tasks/presentation/widgets/recurrence_picker.dart):
```dart
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
```

## Commands you will need

| Purpose   | Command                                 | Expected on success |
|-----------|-----------------------------------------|---------------------|
| Run tests | `flutter test`                          | exit 0, all pass    |
| Analyze   | `flutter analyze`                       | exit 0, no issues   |

## Scope

**In scope**:
- `lib/features/tasks/domain/task_recurrence.dart`
- `lib/features/tasks/presentation/widgets/recurrence_picker.dart`
- `lib/features/tasks/presentation/widgets/task_metadata_sheet.dart`
- `lib/features/tasks/presentation/widgets/task_metadata_badges.dart`
- `test/features/tasks/presentation/widgets/task_metadata_sheet_test.dart`
- `test/features/tasks/presentation/widgets/task_metadata_badges_test.dart`
- `test/features/tasks/presentation/widgets/task_tile_test.dart`

**Out of scope**:
- Modifications to database models or Go backend services (the data representation remains unchanged).

## Git workflow

- Branch: `advisor/001-dynamic-recurrence-labels`
- Commit per step; message style: Conventional Commits (e.g. `feat(tasks): update recurrence label dynamically`).

---

## Steps

### Step 1: Initialize Date Formatting in existing test files

Before writing formatting logic using `DateFormat` with the `'pt_BR'` locale in presentation code, we must ensure the test files initialize date formatting to prevent `LocaleDataException` crashes during widget testing.

Modify `test/features/tasks/presentation/widgets/task_metadata_sheet_test.dart`, `test/features/tasks/presentation/widgets/task_metadata_badges_test.dart`, and `test/features/tasks/presentation/widgets/task_tile_test.dart` to import `intl` and call `initializeDateFormatting('pt_BR', null)` in a `setUpAll` block:

```dart
import 'package:intl/date_symbol_data_local.dart'; // Add this import

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR', null);
  });
...
```

**Verify**: `flutter test` -> all tests pass.

### Step 2: Implement dynamic localized labels in `TaskRecurrenceUI` extension

Modify [task_recurrence.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/tasks/domain/task_recurrence.dart) to define a helper extension method `getLocalizedLabel(DateTime? dueDate)` to centralize UI formatting logic:

```dart
import 'package:intl/intl.dart'; // Add import

extension TaskRecurrenceUI on TaskRecurrence {
  ...
  String getLocalizedLabel(DateTime? dueDate) {
    if (dueDate == null) return label;
    switch (this) {
      case TaskRecurrence.daily:
      case TaskRecurrence.weekdays:
        return label;
      case TaskRecurrence.weekly:
        final weekday = DateFormat.EEEE('pt_BR').format(dueDate);
        return 'Semanalmente ($weekday)';
      case TaskRecurrence.monthly:
        final day = DateFormat('d').format(dueDate);
        return 'Mensalmente (dia $day)';
    }
  }
}
```

**Verify**: `flutter analyze` -> no analyzer errors.

### Step 3: Update `RecurrencePicker` to accept `dueDate` and display dynamic labels

Modify [recurrence_picker.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/tasks/presentation/widgets/recurrence_picker.dart):
1. Add `dueDate` parameter to the constructor.
2. In the `build` loop, pass `dueDate` to `option.getLocalizedLabel(dueDate)`.

```dart
class RecurrencePicker extends StatelessWidget {
  const RecurrencePicker({
    super.key,
    required this.initialRecurrence,
    required this.onChanged,
    this.dueDate, // Add this
  });

  final TaskRecurrence? initialRecurrence;
  final ValueChanged<TaskRecurrence?> onChanged;
  final DateTime? dueDate; // Add this

  @override
  Widget build(BuildContext context) {
    ...
        for (final option in TaskRecurrence.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppSelectionTile(
              label: option.getLocalizedLabel(dueDate), // Update this
              icon: option.icon,
              isSelected: option == initialRecurrence,
              onTap: () => onChanged(option),
            ),
          ),
```

**Verify**: `flutter analyze` -> no analyzer errors.

### Step 4: Pass `dueDate` to `RecurrencePicker` in `TaskMetadataSheet`

Modify [task_metadata_sheet.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/tasks/presentation/widgets/task_metadata_sheet.dart) to pass `_dueDate` state to `RecurrencePicker`:

```dart
          RecurrencePicker(
            initialRecurrence: _recurrence,
            dueDate: _dueDate, // Add this
            onChanged: (r) => setState(() {
              _recurrence = r;
              if (r != null && _dueDate == null) {
                _dueDate = DateTime.now().startOfDay;
              }
            }),
          ),
```

**Verify**: `flutter test` -> all tests pass.

### Step 5: Update `TaskMetadataBadges` to display dynamic labels

Ensure that the task list UI and other places that display the recurrence badge match the dynamic formatting of the picker.
Modify [task_metadata_badges.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/tasks/presentation/widgets/task_metadata_badges.dart) to use `recurrence!.getLocalizedLabel(dueDate)`:

```dart
        if (_hasRecurrence)
          _MetadataPill(
            icon: Icons.refresh,
            label: recurrence!.getLocalizedLabel(dueDate), // Update this
            color: scheme.onSurfaceVariant,
          ),
```

**Verify**: `flutter test` -> all tests pass.

---

## Test plan

- **Locale safety check**: Verify that running the test suite completes without any formatting locale crashes.
- **Dynamic Weekly Recurrence in Bottom Sheet**:
  - Write a new widget test in `test/features/tasks/presentation/widgets/task_metadata_sheet_test.dart` that builds a `TaskMetadataSheet` with a task due on a Thursday and weekly recurrence, verifying that a tile with text "Semanalmente (quinta-feira)" is displayed.
- **Dynamic Monthly Recurrence in Bottom Sheet**:
  - Write a new widget test verifying that a task due on the 15th of a month with monthly recurrence displays a tile with text "Mensalmente (dia 15)".
- **Metadata Badges rendering**:
  - Update `test/features/tasks/presentation/widgets/task_metadata_badges_test.dart` to assert that when both `dueDate` and `recurrence` are present, the dynamic label is displayed (e.g. "Semanalmente (quinta-feira)" or "Mensalmente (dia 15)").
- **Verification Command**:
  - `flutter test` -> all tests pass.

---

## Done criteria

- [ ] `flutter analyze` exits with 0 (no warnings or errors).
- [ ] `flutter test` exits with 0 (all unit/widget tests pass).
- [ ] Weekly recurrence displays the day of the week when a due date is set.
- [ ] Monthly recurrence displays the day of the month when a due date is set.
- [ ] Standard labels ("Semanalmente", "Mensalmente") are displayed as fallbacks when no due date is set.
- [ ] No files outside the in-scope list are modified.

---

## STOP conditions

- If `initializeDateFormatting` fails to run or throws an exception in the test setups.
- If a step's verification fails twice after trying to resolve it.

---

## Maintenance notes

- Any future additions of recurrence types must be implemented inside `TaskRecurrence` and its `TaskRecurrenceUI` extension methods to maintain this localized label formatting convention.
- Ensure that tests added to the project that use locales also initialize them properly.

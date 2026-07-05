# Spec: Dynamic Task Recurrence Labels in Picker

## Goal
To improve the user experience when setting task recurrence by displaying a localized description of the scheduled repetition pattern directly on the selection tiles of the recurrence picker, based on the currently selected due date.

Specifically:
- When a due date is selected and the recurrence is set to **weekly**, display the day of the week (e.g., *"Semanalmente (quinta-feira)"*).
- When a due date is selected and the recurrence is set to **monthly**, display the day of the month (e.g., *"Mensalmente (dia 15)"*).
- If no due date is selected or if the recurrence is daily or weekdays, keep the standard labels.

---

## Design Details

### 1. Update `RecurrencePicker`
We will update [recurrence_picker.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/tasks/presentation/widgets/recurrence_picker.dart) to accept an optional `DateTime? dueDate` parameter:
```dart
class RecurrencePicker extends StatelessWidget {
  const RecurrencePicker({
    super.key,
    required this.initialRecurrence,
    required this.onChanged,
    this.dueDate,
  });

  final TaskRecurrence? initialRecurrence;
  final ValueChanged<TaskRecurrence?> onChanged;
  final DateTime? dueDate;
```

We will implement a helper method `_getLabel` that uses the `intl` package:
```dart
  String _getLabel(TaskRecurrence option, BuildContext context) {
    if (dueDate == null) return option.label;

    switch (option) {
      case TaskRecurrence.daily:
      case TaskRecurrence.weekdays:
        return option.label;
      case TaskRecurrence.weekly:
        final weekday = DateFormat.EEEE('pt_BR').format(dueDate!);
        return 'Semanalmente ($weekday)';
      case TaskRecurrence.monthly:
        final day = DateFormat('d').format(dueDate!);
        return 'Mensalmente (dia $day)';
    }
  }
```

And update the selection tiles builder:
```dart
        for (final option in TaskRecurrence.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppSelectionTile(
              label: _getLabel(option, context),
              icon: option.icon,
              isSelected: option == initialRecurrence,
              onTap: () => onChanged(option),
            ),
          ),
```

### 2. Update `TaskMetadataSheet`
In [task_metadata_sheet.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/tasks/presentation/widgets/task_metadata_sheet.dart), we will pass the `_dueDate` state to `RecurrencePicker`:
```dart
          RecurrencePicker(
            initialRecurrence: _recurrence,
            dueDate: _dueDate,
            onChanged: (r) => setState(() {
              _recurrence = r;
              if (r != null && _dueDate == null) {
                _dueDate = DateTime.now().startOfDay;
              }
            }),
          ),
```

---

## Verification Plan

### Manual Verification
1. Open the task actions sheet by long pressing a task.
2. Verify that without a due date, the recurrence picker displays:
   - "Semanalmente"
   - "Mensalmente"
3. Select "Hoje" (or another specific date, e.g. Thursday, 9th of July).
4. Verify that the recurrence picker options automatically update to display the dynamic labels, for example:
   - "Semanalmente (quinta-feira)"
   - "Mensalmente (dia 9)"
5. Select "Sem data". Verify that the labels revert back to the default "Semanalmente" and "Mensalmente".
6. Select any option and press "Salvar", verifying the sheet closes and the metadata is persisted correctly.

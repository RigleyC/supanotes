# Dynamic Task Recurrence Labels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Display dynamic localized descriptions of recurrence schedules (e.g., "Semanalmente (quinta-feira)") on selection tiles of the RecurrencePicker based on the selected due date.

**Architecture:** We will pass the currently selected due date from `TaskMetadataSheet` to `RecurrencePicker`. Inside `RecurrencePicker`, we will dynamically calculate option labels using the `intl` package for formatting dates.

**Tech Stack:** Flutter, Dart, `intl` package

---

### Task 1: Update RecurrencePicker Component

**Files:**
- Modify: `lib/features/tasks/presentation/widgets/recurrence_picker.dart`

- [ ] **Step 1: Add import for `intl` package and update constructor**
  
  Add `import 'package:intl/intl.dart';` to the imports of [recurrence_picker.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/tasks/presentation/widgets/recurrence_picker.dart).
  Update the class properties and constructor of `RecurrencePicker` to accept `DateTime? dueDate`.

  ```dart
  import 'package:flutter/material.dart';
  import 'package:intl/intl.dart'; // Add import
  import 'package:supanotes/shared/widgets/app_selection_tile.dart';
  import '../../domain/task_recurrence.dart';

  class RecurrencePicker extends StatelessWidget {
    const RecurrencePicker({
      super.key,
      required this.initialRecurrence,
      required this.onChanged,
      this.dueDate, // Add property
    });

    final TaskRecurrence? initialRecurrence;
    final ValueChanged<TaskRecurrence?> onChanged;
    final DateTime? dueDate; // Add property
  ```

- [ ] **Step 2: Add `_getLabel` helper method**
  
  Add `_getLabel` method to `RecurrencePicker`:

  ```dart
    String _getLabel(TaskRecurrence option) {
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

- [ ] **Step 3: Update `AppSelectionTile` labels in the build loop**

  Replace the `label` parameter inside the `for` loop in `build`:

  ```dart
        for (final option in TaskRecurrence.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppSelectionTile(
              label: _getLabel(option),
              icon: option.icon,
              isSelected: option == initialRecurrence,
              onTap: () => onChanged(option),
            ),
          ),
  ```

- [ ] **Step 4: Commit changes**

  Run:
  ```bash
  git add lib/features/tasks/presentation/widgets/recurrence_picker.dart
  git commit -m "feat: add dynamic recurrence labels based on due date"
  ```

---

### Task 2: Pass `dueDate` to `RecurrencePicker` in `TaskMetadataSheet`

**Files:**
- Modify: `lib/features/tasks/presentation/widgets/task_metadata_sheet.dart`

- [ ] **Step 1: Pass `_dueDate` state to `RecurrencePicker`**

  In [task_metadata_sheet.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/tasks/presentation/widgets/task_metadata_sheet.dart), find the `RecurrencePicker` instantiation and add `dueDate: _dueDate,` to its arguments:

  ```dart
            RecurrencePicker(
              initialRecurrence: _recurrence,
              dueDate: _dueDate, // Add property
              onChanged: (r) => setState(() {
                _recurrence = r;
                if (r != null && _dueDate == null) {
                  _dueDate = DateTime.now().startOfDay;
                }
              }),
            ),
  ```

- [ ] **Step 2: Commit changes**

  Run:
  ```bash
  git add lib/features/tasks/presentation/widgets/task_metadata_sheet.dart
  git commit -m "feat: pass selected due date to RecurrencePicker"
  ```

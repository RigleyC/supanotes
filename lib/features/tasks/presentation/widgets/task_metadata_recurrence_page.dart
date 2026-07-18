import 'package:family_bottom_sheet/family_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/shared/widgets/app_selection_tile.dart';

class TaskMetadataRecurrencePage extends StatelessWidget {
  const TaskMetadataRecurrencePage({
    super.key,
    required this.selected,
    required this.dueDate,
    required this.onSelected,
  });

  final TaskRecurrence? selected;
  final DateTime? dueDate;
  final ValueChanged<TaskRecurrence?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
          child: Text(
            'Repetição',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        AppSelectionTile(
          label: 'Nenhuma',
          icon: Icons.do_not_disturb_on_outlined,
          isSelected: selected == null,
          onTap: () {
            onSelected(null);
            FamilyModalSheet.of(context).popPage();
          },
        ),
        ListView.builder(
          shrinkWrap: true,
          itemBuilder: (context, index) {
            final recurrence = TaskRecurrence.values[index];

            return AppSelectionTile(
              label: recurrence.label,
              icon: recurrence.icon,
              isSelected: selected == recurrence,
              onTap: () {
                onSelected(recurrence);
                FamilyModalSheet.of(context).popPage();
              },
            );
          },
          itemCount: TaskRecurrence.values.length,
        ),
        SizedBox(height: 24),
      ],
    );
  }
}

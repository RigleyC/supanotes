import 'package:family_bottom_sheet/family_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:supanotes/features/tasks/domain/task_reminder_option.dart';
import 'package:supanotes/shared/widgets/app_selection_tile.dart';

class TaskMetadataReminderPage extends StatelessWidget {
  const TaskMetadataReminderPage({
    super.key,
    required this.selected,
    required this.hasTime,
    required this.onSelected,
  });

  final TaskReminderOption? selected;
  final bool hasTime;
  final ValueChanged<TaskReminderOption?> onSelected;

  @override
  Widget build(BuildContext context) {
    final options = TaskReminderOption.values
        .where((o) => o.isRelative == hasTime);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
          child: Text(
            'Lembrete',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        AppSelectionTile(
          label: 'Nenhum',
          icon: Icons.do_not_disturb_on_outlined,
          isSelected: selected == null,
          onTap: () {
            onSelected(null);
            FamilyModalSheet.of(context).popPage();
          },
        ),
        ...options.map((option) => AppSelectionTile(
          label: option.label,
          icon: Icons.notifications_outlined,
          isSelected: selected == option,
          onTap: () {
            onSelected(option);
            FamilyModalSheet.of(context).popPage();
          },
        )),
        const SizedBox(height: 24),
      ],
    );
  }
}

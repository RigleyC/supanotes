import 'package:flutter/material.dart';
import 'package:supanotes/features/tasks/domain/task_list_item.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_badges.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_source_label.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_card.dart';
import 'package:supanotes/shared/widgets/app_task_checkbox.dart';
import 'package:supanotes/shared/widgets/app_tile.dart';

class TaskListTile extends StatelessWidget {
  const TaskListTile({
    required this.item,
    required this.onTap,
    this.onToggle,
    super.key,
  });

  final TaskListItem item;
  final VoidCallback onTap;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final recurrence = TaskRecurrence.parse(
      item.isStandalone ? item.task!.recurrenceRule : item.note!.recurrenceRule,
    );
    final reminder = item.isStandalone && item.task!.reminder != null;
    return AppCard(
      padding: EdgeInsets.zero,
      child: AppTile(
        title: item.isStandalone ? item.task!.title : item.note!.title,
        subtitleWidget: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpacing.xs,
          children: [
            TaskSourceLabel(item: item),
            TaskMetadataBadges(
              dueDate: item.dueDate,
              recurrence: recurrence,
              hasReminder: reminder,
              hasTime: item.hasTime,
              now: DateTime.now(),
            ),
          ],
        ),
        leading: GestureDetector(
          key: ValueKey('task-toggle-${item.uiKey}'),
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: const AppTaskCheckbox(value: false),
        ),
        onTap: onTap,
      ),
    );
  }
}

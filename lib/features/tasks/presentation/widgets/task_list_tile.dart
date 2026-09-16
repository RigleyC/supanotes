import 'package:flutter/material.dart';
import 'package:supanotes/features/tasks/domain/task_list_item.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_badges.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_source_label.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_task_checkbox.dart';

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
    final title = item.isStandalone ? item.task?.title : item.note?.title;
    final recurrence = TaskRecurrence.parse(
      item.isStandalone ? item.task?.recurrenceRule : item.note?.recurrenceRule,
    );
    final reminder = item.isStandalone && item.task?.reminder != null;
    final hasMetadata = item.dueDate != null || recurrence != null || reminder;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        spacing: AppSpacing.md,
        children: [
          Semantics(
            button: onToggle != null,
            enabled: onToggle != null,
            child: GestureDetector(
              key: ValueKey('task-toggle-${item.uiKey}'),
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Center(child: AppTaskCheckbox(value: false)),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpacing.xs,
                children: [
                  if (title != null && title.isNotEmpty)
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  TaskSourceLabel(item: item),
                  if (hasMetadata)
                    TaskMetadataBadges(
                      dueDate: item.dueDate,
                      recurrence: recurrence,
                      hasReminder: reminder,
                      hasTime: item.hasTime,
                      now: DateTime.now(),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

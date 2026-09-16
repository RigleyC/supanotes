import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supanotes/features/tasks/domain/task_history_entry.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_source_label.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_card.dart';
import 'package:supanotes/shared/widgets/app_task_checkbox.dart';
import 'package:supanotes/shared/widgets/app_tile.dart';

class CompletedTasksTile extends StatelessWidget {
  const CompletedTasksTile({
    required this.entry,
    required this.onTap,
    super.key,
  });

  final TaskHistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = entry.task.isStandalone
        ? entry.task.task!.title
        : entry.task.note!.title;
    return AppCard(
      padding: EdgeInsets.zero,
      child: AppTile(
        title: title,
        subtitleWidget: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpacing.xs,
          children: [
            TaskSourceLabel(item: entry.task),
            Text(
              'Concluída em ${DateFormat('dd/MM/yyyy HH:mm').format(entry.completedAt.toLocal())}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        leading: const AppTaskCheckbox(value: true),
        onTap: onTap,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_badges.dart';
import 'package:supanotes/shared/theme/app_colors.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_task_checkbox.dart';

import '../../domain/task_model.dart';

class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    this.onToggleComplete,
    this.onOpenMetadata,
    this.dense = false,
  });

  final TaskModel task;
  final ValueChanged<bool>? onToggleComplete;
  final VoidCallback? onOpenMetadata;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantics = theme.extension<AppSemanticColors>();
    final taskColor = semantics?.task ?? AppColors.taskAccent;
    final isCompleted = task.isCompleted;

    final titleColor = isCompleted ? scheme.onSurfaceVariant : scheme.onSurface;
    final titleDecoration =
        isCompleted ? TextDecoration.lineThrough : null;

    return Material(
      color: taskColor.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggleComplete == null
            ? null
            : () => onToggleComplete!(!isCompleted),
        onLongPress: onOpenMetadata,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: dense ? AppSpacing.sm : AppSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppTaskCheckbox(
                value: isCompleted,
                accentColor: taskColor,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      task.title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: titleColor,
                        decoration: titleDecoration,
                        decorationColor: titleColor,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (task.dueDate != null || task.recurrence != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      TaskMetadataBadges(
                        dueDate: task.dueDate,
                        recurrence: task.recurrence,
                        isCompleted: isCompleted,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

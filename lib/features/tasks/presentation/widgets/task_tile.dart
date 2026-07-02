import 'package:flutter/material.dart';
import 'package:supanotes/shared/theme/app_colors.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';

import '../../domain/task_model.dart';
import 'task_checkbox.dart';
import 'task_metadata_badges.dart';

/// Row widget that renders a single [TaskModel] with strikethrough-on-
/// complete styling, a due-date badge coloured by urgency, a small
/// recurrence glyph, and swipe gestures (right = complete, left = delete).
///
/// Pure presentation: it never reads or writes the database directly.
/// All callbacks are owned by the caller.
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    this.onTap,
    this.onToggleComplete,
    this.onDelete,
    this.dense = false,
  });

  final TaskModel task;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onToggleComplete;
  final VoidCallback? onDelete;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantics = theme.extension<AppSemanticColors>();
    final taskColor = semantics?.task ?? AppColors.taskAccent;
    final isCompleted = task.isCompleted;

    final titleColor = isCompleted ? scheme.onSurfaceVariant : scheme.onSurface;
    final titleDecoration = isCompleted ? TextDecoration.lineThrough : null;

    return Dismissible(
      key: ValueKey('task-${task.id}'),
      background: _SwipeBackground(
        alignment: Alignment.centerLeft,
        color: AppColors.success,
        icon: Icons.check_circle_outline,
        label: 'Concluir',
      ),
      secondaryBackground: _SwipeBackground(
        alignment: Alignment.centerRight,
        color: scheme.error,
        icon: Icons.delete_outline,
        label: 'Excluir',
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          if (!isCompleted) onToggleComplete?.call(true);
          return false;
        }
        if (direction == DismissDirection.endToStart) {
          onDelete?.call();
          return false;
        }
        return false;
      },
      child: Material(
        color: taskColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: dense ? AppSpacing.sm : AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                TaskCheckbox(
                  checked: isCompleted,
                  onChanged: (v) => onToggleComplete?.call(v),
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
                        _MetaRow(task: task),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.task});
  final TaskModel task;

  @override
  Widget build(BuildContext context) {
    return TaskMetadataBadges(
      dueDate: task.dueDate,
      recurrence: task.recurrence,
      isCompleted: task.isCompleted,
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

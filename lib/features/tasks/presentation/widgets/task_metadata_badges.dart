import 'package:flutter/material.dart';
import 'package:supanotes/core/utils/date_time_extensions.dart';
import 'package:supanotes/features/tasks/domain/task_date_format.dart';
import 'package:supanotes/shared/theme/app_colors.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';

import '../../domain/task_recurrence.dart';

class TaskMetadataBadges extends StatelessWidget {
  const TaskMetadataBadges({
    super.key,
    this.dueDate,
    this.recurrence,
    this.hasReminder = false,
    this.isCompleted = false,
    this.hasTime = false,
    this.now,
  });

  final DateTime? dueDate;
  final TaskRecurrence? recurrence;
  final bool hasReminder;
  final bool isCompleted;
  final bool hasTime;
  final DateTime? now;

  bool get _hasRecurrence => recurrence != null;
  bool get _hasDueDate => dueDate != null;

  @override
  Widget build(BuildContext context) {
    if (!_hasDueDate && !_hasRecurrence && !hasReminder) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (_hasDueDate)
          _MetadataPill(
            icon: Icons.event_outlined,
            label: formatDueDate(
              dueDate!,
              hasTime: hasTime,
              isCompleted: isCompleted,
              now: now,
            ),
            color: _dueDateColor(context, dueDate!),
          ),
        if (_hasRecurrence)
          _MetadataPill(
            icon: Icons.refresh,
            label: recurrence!.shortLabel,
            color: scheme.onSurfaceVariant,
          ),
        if (hasReminder)
          Icon(
            Icons.notifications_active_outlined,
            size: 14,
            color: scheme.onSurfaceVariant,
          ),
      ],
    );
  }

  Color _dueDateColor(BuildContext context, DateTime dueDate) {
    if (isCompleted) {
      return Theme.of(context).colorScheme.onSurfaceVariant;
    }

    final effectiveNow = now ?? DateTime.now();
    final today = effectiveNow.startOfDay;
    final date = dueDate.startOfDay;

    if (date.isBefore(today)) return Theme.of(context).colorScheme.error;

    if (date.isSameDayAs(today)) {
      // If the task has a specific time and it has already passed, show as overdue
      if (hasTime && dueDate.isBefore(effectiveNow)) {
        return Theme.of(context).colorScheme.error;
      }
      return AppColors.success;
    }

    return Theme.of(context).colorScheme.onSurfaceVariant;
  }
}

class _MetadataPill extends StatelessWidget {
  const _MetadataPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

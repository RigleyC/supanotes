import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supanotes/core/utils/date_time_extensions.dart';
import 'package:supanotes/shared/theme/app_colors.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';

import '../../domain/task_recurrence.dart';
import 'recurrence_picker.dart';

class TaskMetadataBadges extends StatelessWidget {
  const TaskMetadataBadges({super.key, this.dueDate, this.recurrence});

  final DateTime? dueDate;
  final TaskRecurrence? recurrence;

  bool get _hasRecurrence => recurrence != null;
  bool get _hasDueDate => dueDate != null;

  @override
  Widget build(BuildContext context) {
    if (!_hasDueDate && !_hasRecurrence) {
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
            label: _dueDateLabel(dueDate!),
            color: _dueDateColor(context, dueDate!),
          ),
        if (_hasRecurrence)
          _MetadataPill(
            icon: Icons.refresh,
            label: recurrenceLabel(recurrence),
            color: scheme.onSurfaceVariant,
          ),
      ],
    );
  }

  String _dueDateLabel(DateTime dueDate) {
    final today = DateTime.now().startOfDay;
    final date = dueDate.startOfDay;

    if (date.isSameDayAs(today)) return 'Hoje';
    if (date.isBefore(today)) {
      return 'Atrasada \u00b7 ${DateFormat('d MMM').format(dueDate)}';
    }
    return DateFormat('d MMM').format(dueDate);
  }

  Color _dueDateColor(BuildContext context, DateTime dueDate) {
    final today = DateTime.now().startOfDay;
    final date = dueDate.startOfDay;
    
    if (date.isBefore(today)) return Theme.of(context).colorScheme.error;
    if (date.isSameDayAs(today)) return AppColors.success;
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
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}

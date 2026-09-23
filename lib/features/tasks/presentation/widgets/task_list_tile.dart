import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supanotes/features/tasks/domain/task_list_item.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_badges.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_source_label.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_task_checkbox.dart';
import 'package:supanotes/shared/widgets/task_exit_animator.dart';

class TaskListTile extends StatefulWidget {
  const TaskListTile({
    required this.item,
    required this.onTap,
    this.onToggle,
    this.checked = false,
    this.completedAt,
    super.key,
  });

  final TaskListItem item;
  final VoidCallback onTap;
  final Future<void> Function()? onToggle;
  final bool checked;
  final DateTime? completedAt;

  @override
  State<TaskListTile> createState() => _TaskListTileState();
}

class _TaskListTileState extends State<TaskListTile> {
  bool? _optimisticChecked;

  // `DateFormat` construction does locale-data lookup: far too expensive to
  // rebuild for every tile on every list emission.
  static final _completedAtFormat = DateFormat('dd/MM/yyyy HH:mm');

  void _toggleTask() {
    if (widget.onToggle == null || _optimisticChecked != null) return;
    setState(() => _optimisticChecked = !widget.checked);
    unawaited(_completeTask());
  }

  Future<void> _completeTask() async {
    try {
      await widget.onToggle!();
    } catch (_) {
      if (mounted) setState(() => _optimisticChecked = null);
    }
  }

  @override
  void didUpdateWidget(covariant TaskListTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.uiKey != widget.item.uiKey ||
        oldWidget.item.dueDate != widget.item.dueDate ||
        (_optimisticChecked != null && widget.checked == _optimisticChecked)) {
      _optimisticChecked = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final title = item.isStandalone ? item.task?.title : item.note?.title;
    final recurrence = TaskRecurrence.parse(
      item.isStandalone ? item.task?.recurrenceRule : item.note?.recurrenceRule,
    );
    final reminder = item.isStandalone && item.task?.reminder != null;
    final hasMetadata = item.dueDate != null || recurrence != null || reminder;

    return TaskExitAnimator(
      hideCompleted: false,
      isComplete: _optimisticChecked ?? widget.checked,
      onAnimationComplete: null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          spacing: AppSpacing.md,
          children: [
            Semantics(
              button: widget.onToggle != null,
              enabled: widget.onToggle != null,
              child: GestureDetector(
                key: ValueKey('task-toggle-${item.uiKey}'),
                behavior: HitTestBehavior.opaque,
                onTap: _toggleTask,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: AppTaskCheckbox(
                      size: 20,
                      value: _optimisticChecked ?? widget.checked,
                      shape: AppTaskCheckboxShape.rounded,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
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
                        isCompleted: widget.checked || item.isCompleted,
                        now: DateTime.now(),
                      ),
                    if (widget.completedAt != null)
                      Text(
                        'Concluída em ${_completedAtFormat.format(widget.completedAt!.toLocal())}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

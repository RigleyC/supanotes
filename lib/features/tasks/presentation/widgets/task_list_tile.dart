import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/task_text_style_resolver.dart';
import 'package:supanotes/features/tasks/domain/task_list_item.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_badges.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_source_label.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_task_checkbox.dart';
import 'package:supanotes/shared/widgets/confirm_dialog.dart';
import 'package:supanotes/shared/widgets/task_exit_animator.dart';

class TaskListTile extends StatefulWidget {
  const TaskListTile({
    required this.item,
    required this.onTap,
    this.onToggle,
    this.onDelete,
    this.checked = false,
    this.completedAt,
    this.trailingLabel,
    this.trailingColor,
    super.key,
  });

  final TaskListItem item;
  final VoidCallback onTap;
  final Future<void> Function()? onToggle;
  final Future<void> Function()? onDelete;
  final bool checked;
  final DateTime? completedAt;

  /// Short schedule shown at the end of a compact row ("14:30", "sáb").
  final String? trailingLabel;

  /// Color of [trailingLabel]; defaults to the secondary grey.
  final Color? trailingColor;

  /// Rows with a [completedAt] (completion history) keep the detailed layout
  /// with source and schedule metadata; open-task rows are a single line.
  bool get _detailed => completedAt != null;

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
    final isChecked = _optimisticChecked ?? widget.checked;

    final tile = TaskExitAnimator(
      hideCompleted: false,
      isComplete: isChecked,
      onAnimationComplete: null,
      child: Padding(
        // Compact rows get air too, so a list of tasks does not read as one
        // block (56 px rows).
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          spacing: widget._detailed ? AppSpacing.md : 0,
          children: [
            Semantics(
              button: widget.onToggle != null,
              enabled: widget.onToggle != null,
              checked: isChecked,
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
                      value: isChecked,
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
                child: widget._detailed
                    ? _buildDetails(context, title)
                    : _buildCompact(context, title, isChecked),
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.onDelete == null) return tile;

    return Dismissible(
      key: ValueKey('task-dismiss-${item.uiKey}'),
      direction: DismissDirection.endToStart,
      background: const SizedBox.shrink(),
      secondaryBackground: ColoredBox(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            child: Icon(
              Icons.delete_outline_rounded,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
        ),
      ),
      confirmDismiss: (_) async {
        return showConfirmDialog(
          context: context,
          title: 'Excluir task?',
          message: 'Essa task será removida da sua lista.',
          confirmLabel: 'Excluir',
          destructive: true,
        );
      },
      onDismissed: (_) => unawaited(widget.onDelete!()),
      child: tile,
    );
  }

  Widget _buildCompact(BuildContext context, String? title, bool isChecked) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titleStyle = resolveTaskTextStyle(
      (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
        fontSize: 18,
        height: 1.3,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.1,
      ),
      scheme.onSurface,
      isChecked,
    );
    final trailing = widget.trailingLabel;
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
            ),
          ),
          if (trailing != null && trailing.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.md),
            Text(
              trailing,
              key: ValueKey('task-trailing-${widget.item.uiKey}'),
              maxLines: 1,
              style: (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
                fontSize: 14,
                height: 1.3,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
                color:
                    widget.trailingColor ??
                    scheme.onSurfaceVariant.withValues(alpha: 0.8),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetails(BuildContext context, String? title) {
    final item = widget.item;
    final recurrence = TaskRecurrence.parse(
      item.isStandalone ? item.task?.recurrenceRule : item.note?.recurrenceRule,
    );
    final reminder = item.isStandalone && item.task?.reminder != null;
    final hasMetadata = item.dueDate != null || recurrence != null || reminder;
    return Column(
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
        Text(
          'Concluída em '
          '${_completedAtFormat.format(widget.completedAt!.toLocal())}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

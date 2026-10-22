import 'dart:async' show Timer, unawaited;

import 'package:flutter/material.dart';
import 'package:supanotes/core/utils/recurrence.dart';
import 'package:supanotes/core/utils/app_haptics.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/custom_list_item_component.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/task_text_style_resolver.dart';
import 'package:supanotes/features/tasks/domain/task_completion_state.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_occurrence.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_metadata_draft.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_badges.dart';
import 'package:supanotes/shared/theme/app_colors.dart';
import 'package:supanotes/shared/widgets/app_task_checkbox.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/shared/widgets/task_exit_animator.dart';

const double _taskCheckboxSize = 20;
const double _taskCheckboxFallbackTopInset = 2;
const double _taskCheckboxTextGap = noteEditorMarkerTextGap;
const double _taskTopSpacing = 14;
const double _taskCheckboxTouchHeight = 44;

const _occurrencePolicy = TaskOccurrencePolicy();

/// Slack that keeps cache pruning rare while still bounding entries for task
/// blocks that no longer exist in the document.
const int _occurrenceCacheSlack = 16;

int _localDayKey() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
}

final class _TaskOccurrenceMemo {
  const _TaskOccurrenceMemo({
    required this.metadata,
    required this.day,
    required this.occurrence,
  });

  final TaskMetadataDraft metadata;
  final int day;
  final TaskOccurrence? occurrence;
}

class CustomTaskComponentBuilder implements ComponentBuilder {
  CustomTaskComponentBuilder({
    this.hideCompleted = false,
    this.readOnly = false,
    this.onTaskLongPress,
    this.onTaskComplete,
    this.onTaskReopen,
  });

  bool hideCompleted;
  final bool readOnly;
  ValueChanged<String>? onTaskLongPress;
  final Future<DateTime?> Function(String taskId)? onTaskComplete;
  final Future<void> Function(String taskId, DateTime? scheduledAt)?
  onTaskReopen;

  final Map<String, _TaskOccurrenceMemo> _occurrenceByNodeId = {};

  @override
  TaskComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is! TaskNode) return null;

    final metadata = TaskMetadataDraft.fromTaskNode(node);
    final isRecurring = metadata.recurrence != null;
    final occurrence = _resolveOccurrence(document, node.id, metadata);
    final isComplete = isTaskOccurrenceCompleted(
      isComplete: node.isComplete,
      recurrence: metadata.recurrence,
      occurrence: occurrence,
    );

    Future<void> updateCompletion(bool isComplete) async {
      if (readOnly) return;
      unawaited(AppHaptics.taskCompletion());
      if (isComplete) {
        await onTaskComplete?.call(node.id);
      } else {
        await onTaskReopen?.call(node.id, occurrence?.scheduledAt);
      }
    }

    return CustomTaskComponentViewModel(
      nodeId: node.id,
      createdAt: node.metadata[NodeMetadata.createdAt] as DateTime?,
      padding: EdgeInsets.zero,
      indent: node.indent,
      isComplete: isComplete,
      setComplete: (isComplete) => unawaited(updateCompletion(isComplete)),
      text: node.text,
      textDirection: getParagraphDirection(node.text.toPlainText()),
      textAlignment: TextAlign.left,
      textStyleBuilder: noStyleBuilder,
      selectionColor: const Color(0x00000000),
      dueDate: metadata.scheduleAnchor,
      recurrence: metadata.recurrence,
      taskMetadata: metadata,
      isRecurring: isRecurring,
      resolvedOccurrenceDate: occurrence?.scheduledAt,
      onCompletionChange: updateCompletion,
    );
  }

  /// Resolving an occurrence walks every date between the task anchor and
  /// today, and the view model layer runs for each visible block on every
  /// document change. Task metadata is the only input that can change the
  /// result besides the local day boundary, so both key the cache.
  TaskOccurrence? _resolveOccurrence(
    Document document,
    String nodeId,
    TaskMetadataDraft metadata,
  ) {
    final day = _localDayKey();
    final cached = _occurrenceByNodeId[nodeId];
    if (cached != null && cached.day == day && cached.metadata == metadata) {
      return cached.occurrence;
    }

    _pruneOccurrenceCache(document);
    final occurrence = _occurrencePolicy.resolveCurrent(
      taskId: nodeId,
      anchor: metadata.scheduleAnchor,
      recurrence: metadata.recurrence,
      hasTime: metadata.hasTime,
      completedAtByScheduledAt: metadata.completions,
    );
    _occurrenceByNodeId[nodeId] = _TaskOccurrenceMemo(
      metadata: metadata,
      day: day,
      occurrence: occurrence,
    );
    return occurrence;
  }

  void _pruneOccurrenceCache(Document document) {
    if (_occurrenceByNodeId.length <=
        document.nodeCount + _occurrenceCacheSlack) {
      return;
    }
    final liveNodeIds = {for (final node in document) node.id};
    _occurrenceByNodeId.removeWhere(
      (nodeId, _) => !liveNodeIds.contains(nodeId),
    );
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is! CustomTaskComponentViewModel) return null;

    return CustomTaskComponent(
      key: componentContext.componentKey,
      viewModel: componentViewModel,
      isReadOnly: readOnly,
      hideCompleted: hideCompleted,
      onLongPress: readOnly || onTaskLongPress == null
          ? null
          : () {
              onTaskLongPress!(componentViewModel.nodeId);
            },
    );
  }
}

class CustomTaskComponentViewModel extends TaskComponentViewModel {
  CustomTaskComponentViewModel({
    required super.nodeId,
    required super.createdAt,
    required super.padding,
    required super.indent,
    required super.isComplete,
    required super.setComplete,
    required super.text,
    required super.textDirection,
    required super.textAlignment,
    required super.textStyleBuilder,
    required super.selectionColor,
    required this.taskMetadata,
    required this.isRecurring,
    required this.onCompletionChange,
    super.opacity = 1.0,
    this.dueDate,
    this.recurrence,
    this.resolvedOccurrenceDate,
  });

  final DateTime? dueDate;
  final TaskRecurrence? recurrence;
  final TaskMetadataDraft taskMetadata;
  final bool isRecurring;

  /// Scheduled date of the occurrence that is current when this view model is
  /// built, so the component does not resolve recurrence on every paint.
  final DateTime? resolvedOccurrenceDate;
  final Future<void> Function(bool isComplete)? onCompletionChange;

  @override
  CustomTaskComponentViewModel copy() {
    return super.internalCopy(
          CustomTaskComponentViewModel(
            nodeId: nodeId,
            createdAt: createdAt,
            padding: padding,
            text: text.copy(),
            textStyleBuilder: textStyleBuilder,
            opacity: opacity,
            selectionColor: selectionColor,
            indent: indent,
            isComplete: isComplete,
            setComplete: setComplete,
            textDirection: textDirection,
            textAlignment: textAlignment,
            dueDate: dueDate,
            recurrence: recurrence,
            taskMetadata: taskMetadata,
            isRecurring: isRecurring,
            resolvedOccurrenceDate: resolvedOccurrenceDate,
            onCompletionChange: onCompletionChange,
          ),
        )
        as CustomTaskComponentViewModel;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CustomTaskComponentViewModel) return false;
    if (super != other) return false;
    return dueDate == other.dueDate &&
        recurrence == other.recurrence &&
        taskMetadata == other.taskMetadata &&
        isRecurring == other.isRecurring &&
        resolvedOccurrenceDate == other.resolvedOccurrenceDate;
  }

  @override
  int get hashCode => Object.hash(
    super.hashCode,
    dueDate,
    recurrence,
    taskMetadata,
    isRecurring,
    resolvedOccurrenceDate,
  );
}

class CustomTaskComponent extends StatefulWidget {
  const CustomTaskComponent({
    required this.viewModel,
    super.key,
    this.isReadOnly = false,
    this.hideCompleted = false,
    this.onLongPress,
  });

  final CustomTaskComponentViewModel viewModel;
  final bool isReadOnly;
  final bool hideCompleted;
  final VoidCallback? onLongPress;

  @override
  State<CustomTaskComponent> createState() => _CustomTaskComponentState();
}

class _CustomTaskComponentState extends State<CustomTaskComponent>
    with ProxyDocumentComponent<CustomTaskComponent>, ProxyTextComposable {
  final GlobalKey<State<StatefulWidget>> _textKey = GlobalKey();

  late bool _isComplete;
  late DateTime? _resolvedOccurrenceDate;
  bool _isAnimating = false;
  bool _isUpdatingCompletion = false;
  Timer? _occurrenceBoundaryTimer;

  bool get _isHidden => widget.hideCompleted && _isComplete;

  @override
  void initState() {
    super.initState();
    _isComplete = widget.viewModel.isComplete;
    _resolvedOccurrenceDate = widget.viewModel.resolvedOccurrenceDate;
    _scheduleOccurrenceRefresh();
  }

  @override
  void didUpdateWidget(covariant CustomTaskComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.viewModel.isComplete != oldWidget.viewModel.isComplete) {
      _isComplete = widget.viewModel.isComplete;
    }
    _resolvedOccurrenceDate = widget.viewModel.resolvedOccurrenceDate;
    _scheduleOccurrenceRefresh();
  }

  @override
  void dispose() {
    _occurrenceBoundaryTimer?.cancel();
    super.dispose();
  }

  void _scheduleOccurrenceRefresh() {
    _occurrenceBoundaryTimer?.cancel();
    final metadata = widget.viewModel.taskMetadata;
    final anchor = metadata.scheduleAnchor;
    final recurrence = metadata.recurrence;
    final scheduledAt = _resolvedOccurrenceDate;
    if (anchor == null || recurrence == null || scheduledAt == null) return;
    final next = nextDueDate(
      from: scheduledAt,
      recurrence: recurrence,
      anchorDay: anchor.day,
    );
    if (next == null) return;
    final now = DateTime.now();
    // Visibility changes at the next local date boundary; an open occurrence
    // also changes from pending to overdue at its scheduled wall-clock time.
    final boundaries = <DateTime>[
      scheduledAt,
      DateTime(scheduledAt.year, scheduledAt.month, scheduledAt.day),
      DateTime(next.year, next.month, next.day),
    ].where((boundary) => boundary.isAfter(now));
    if (boundaries.isEmpty) return;
    final boundary = boundaries.reduce(
      (earliest, candidate) =>
          candidate.isBefore(earliest) ? candidate : earliest,
    );
    final delay = boundary.difference(now);
    _occurrenceBoundaryTimer = Timer(delay, _refreshOccurrence);
  }

  void _refreshOccurrence() {
    if (!mounted) return;
    final metadata = widget.viewModel.taskMetadata;
    final occurrence = _occurrencePolicy.resolveCurrent(
      taskId: widget.viewModel.nodeId,
      anchor: metadata.scheduleAnchor,
      recurrence: metadata.recurrence,
      hasTime: metadata.hasTime,
      completedAtByScheduledAt: metadata.completions,
    );
    final completed = isTaskOccurrenceCompleted(
      isComplete: widget.viewModel.isComplete,
      recurrence: metadata.recurrence,
      occurrence: occurrence,
    );
    final resolvedDate = occurrence?.scheduledAt;
    if (completed != _isComplete || resolvedDate != _resolvedOccurrenceDate) {
      setState(() {
        _isComplete = completed;
        _resolvedOccurrenceDate = resolvedDate;
      });
    }
    _scheduleOccurrenceRefresh();
  }

  Future<void> _onCheckboxTap() async {
    if (widget.isReadOnly || _isUpdatingCompletion) {
      return;
    }

    final previousValue = _isComplete;
    final newComplete = !_isComplete;
    setState(() {
      _isComplete = newComplete;
      _isUpdatingCompletion = true;
      if (widget.hideCompleted && newComplete) {
        _isAnimating = true;
      }
    });
    try {
      if (widget.viewModel.onCompletionChange != null) {
        await widget.viewModel.onCompletionChange!(newComplete);
      } else {
        widget.viewModel.setComplete?.call(newComplete);
      }
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() {
          _isComplete = previousValue;
          _isAnimating = false;
        });
      }
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'supanotes note editor',
          context: ErrorDescription('while changing note task completion'),
        ),
      );
      if (mounted) {
        AppMessenger.showError('Não foi possível atualizar a tarefa');
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingCompletion = false);
      }
    }
  }

  void _onTouchLongPress() {
    widget.onLongPress?.call();
  }

  void _onCheckAnimationCompleted() {
    if (!_isAnimating || !mounted) return;
    setState(() => _isAnimating = false);
  }

  @override
  GlobalKey<State<StatefulWidget>> get childDocumentComponentKey => _textKey;

  @override
  TextComposable get childTextComposable =>
      childDocumentComponentKey.currentState! as TextComposable;

  @override
  Rect getRectForPosition(NodePosition nodePosition) {
    if (_isHidden) return Rect.zero;
    return super.getRectForPosition(nodePosition);
  }

  @override
  Offset getOffsetForPosition(NodePosition nodePosition) {
    if (_isHidden) return Offset.zero;
    return super.getOffsetForPosition(nodePosition);
  }

  @override
  NodePosition? getPositionAtOffset(Offset localOffset) {
    if (_isHidden) return null;
    return super.getPositionAtOffset(localOffset);
  }

  @override
  bool isVisualSelectionSupported() => !_isHidden;

  @override
  MouseCursor? getDesiredCursorAtOffset(Offset localOffset) {
    if (_isHidden) return null;
    return super.getDesiredCursorAtOffset(localOffset);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final semantics = Theme.of(context).extension<AppSemanticColors>();
    final taskColor = semantics?.task ?? AppColors.taskAccent;
    final metadata = widget.viewModel.taskMetadata;
    final textStyle = widget.viewModel.textStyleBuilder({});
    final textLineHeight = MediaQuery.textScalerOf(
      context,
    ).scale((textStyle.fontSize ?? 16) * (textStyle.height ?? 1.0));
    final checkboxTopInset = textStyle.height == null
        ? _taskCheckboxFallbackTopInset
        : (textLineHeight - _taskCheckboxSize) / 2;
    const checkboxMarkerWidth = _taskCheckboxSize + _taskCheckboxTextGap;
    final indentUnit = noteEditorIndentUnit(textStyle);
    final levelOffset = indentUnit * widget.viewModel.indent;
    final content = Directionality(
      textDirection: widget.viewModel.textDirection,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTap: widget.onLongPress,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: levelOffset),
            SizedBox(
              width: checkboxMarkerWidth,
              height: _taskCheckboxTouchHeight,
              child: Semantics(
                button: true,
                checked: _isComplete,
                enabled: !widget.isReadOnly && !_isUpdatingCompletion,
                label: _isComplete
                    ? 'Marcar tarefa como pendente'
                    : 'Concluir tarefa',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.isReadOnly || _isUpdatingCompletion
                      ? null
                      : _onCheckboxTap,
                  onLongPress: widget.isReadOnly || widget.onLongPress == null
                      ? null
                      : _onTouchLongPress,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: _taskTopSpacing + checkboxTopInset,
                      ),
                      child: AppTaskCheckbox(
                        size: 20,
                        value: _isComplete,
                        accentColor: taskColor,
                        inactiveColor: colorScheme.outline,
                        shape: AppTaskCheckboxShape.rounded,
                        onCheckAnimationCompleted: widget.isReadOnly
                            ? null
                            : _onCheckAnimationCompleted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: _taskTopSpacing),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextComponent(
                      key: _textKey,
                      text: widget.viewModel.text,
                      textDirection: widget.viewModel.textDirection,
                      textAlign: widget.viewModel.textAlignment,
                      maxLines: widget.viewModel.maxLines,
                      overflow: widget.viewModel.overflow,
                      textStyleBuilder: (attributions) => resolveTaskTextStyle(
                        widget.viewModel.textStyleBuilder(attributions),
                        Theme.of(context).colorScheme.onSurface,
                        _isComplete,
                      ),
                      inlineWidgetBuilders:
                          widget.viewModel.inlineWidgetBuilders,
                      textSelection: widget.viewModel.selection,
                      selectionColor: widget.viewModel.selectionColor,
                      highlightWhenEmpty: widget.viewModel.highlightWhenEmpty,
                      underlines: widget.viewModel.createUnderlines(),
                    ),
                    if (metadata.scheduleAnchor != null ||
                        metadata.recurrence != null ||
                        metadata.reminder != null) ...[
                      const SizedBox(height: 4),
                      TaskMetadataBadges(
                        dueDate: metadata.scheduleAnchor,
                        resolvedOccurrenceDate: _resolvedOccurrenceDate,
                        recurrence: metadata.recurrence,
                        hasReminder: metadata.reminder != null,
                        hasTime: metadata.hasTime,
                        completions: metadata.completions,
                        isCompleted: _isComplete,
                      ),
                      const SizedBox(height: 4),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return TaskExitAnimator(
      hideCompleted: widget.hideCompleted,
      isComplete: _isComplete,
      onAnimationComplete: _isAnimating
          ? () => setState(() => _isAnimating = false)
          : null,
      child: ExcludeSemantics(
        excluding: _isHidden,
        child: IgnorePointer(
          ignoring: _isHidden,
          child: content,
        ),
      ),
    );
  }
}

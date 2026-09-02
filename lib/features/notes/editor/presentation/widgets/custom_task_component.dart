import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:supanotes/core/utils/app_haptics.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/custom_list_item_component.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/task_exit_animator.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/task_text_style_resolver.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_metadata_draft.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_badges.dart';
import 'package:supanotes/shared/theme/app_colors.dart';
import 'package:supanotes/shared/widgets/app_task_checkbox.dart';
import 'package:super_editor/super_editor.dart';

const double _taskCheckboxSize = 20;
const double _taskCheckboxFallbackTopInset = 2;
const double _taskCheckboxTextGap = noteEditorMarkerTextGap;

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
  final Future<void> Function(String taskId)? onTaskReopen;

  @override
  TaskComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is! TaskNode) return null;

    final metadata = TaskMetadataDraft.fromTaskNode(node);
    final isRecurring = isRecurringTaskNode(node);

    Future<void> updateCompletion(bool isComplete) async {
      if (readOnly) return;
      AppHaptics.taskCompletion();
      if (isComplete) {
        await onTaskComplete?.call(node.id);
      } else {
        await onTaskReopen?.call(node.id);
      }
    }

    return CustomTaskComponentViewModel(
      nodeId: node.id,
      createdAt: node.metadata[NodeMetadata.createdAt] as DateTime?,
      padding: EdgeInsets.zero,
      indent: node.indent,
      isComplete: node.isComplete,
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
      onCompletionChange: updateCompletion,
    );
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is! TaskComponentViewModel) return null;

    final customViewModel = componentViewModel is CustomTaskComponentViewModel
        ? componentViewModel
        : null;

    return CustomTaskComponent(
      key: componentContext.componentKey,
      viewModel: componentViewModel,
      taskMetadata: customViewModel?.taskMetadata,
      isRecurring: customViewModel?.isRecurring ?? false,
      isReadOnly: readOnly,
      onCompletionChange: customViewModel?.onCompletionChange,
      hideCompleted: hideCompleted,
      onLongPress: readOnly || onTaskLongPress == null
          ? null
          : () {
              onTaskLongPress!(componentViewModel.nodeId);
            },
    );
  }
}

bool isRecurringTaskNode(TaskNode node) {
  final recurrenceRule = node.metadata['recurrenceRule'];
  return TaskRecurrence.parse(
        recurrenceRule is String ? recurrenceRule : null,
      ) !=
      null;
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
    super.opacity = 1.0,
    this.dueDate,
    this.recurrence,
    required this.isRecurring,
    required this.onCompletionChange,
  });

  final DateTime? dueDate;
  final TaskRecurrence? recurrence;
  final TaskMetadataDraft taskMetadata;
  final bool isRecurring;
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
        isRecurring == other.isRecurring;
  }

  @override
  int get hashCode => Object.hash(
    super.hashCode,
    dueDate,
    recurrence,
    taskMetadata,
    isRecurring,
  );
}

class CustomTaskComponent extends StatefulWidget {
  const CustomTaskComponent({
    required this.viewModel,
    super.key,
    this.isReadOnly = false,
    this.isRecurring = false,
    this.taskMetadata,
    this.hideCompleted = false,
    this.onLongPress,
    this.onCompletionChange,
  });

  final TaskComponentViewModel viewModel;
  final bool isReadOnly;
  final bool isRecurring;
  final TaskMetadataDraft? taskMetadata;
  final bool hideCompleted;
  final VoidCallback? onLongPress;
  final Future<void> Function(bool isComplete)? onCompletionChange;

  @override
  State<CustomTaskComponent> createState() => _CustomTaskComponentState();
}

class _CustomTaskComponentState extends State<CustomTaskComponent>
    with ProxyDocumentComponent<CustomTaskComponent>, ProxyTextComposable {
  final GlobalKey<State<StatefulWidget>> _textKey = GlobalKey();

  late bool _isComplete;
  bool _isAnimating = false;
  bool _isUpdatingCompletion = false;

  bool get _isRecurring => widget.isRecurring;

  bool get _isHidden => widget.hideCompleted && _isComplete && !_isRecurring;

  @override
  void initState() {
    super.initState();
    _isComplete = widget.viewModel.isComplete;
  }

  @override
  void didUpdateWidget(covariant CustomTaskComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isRecurring) {
      if (widget.viewModel.isComplete) {
        _isComplete = false;
      }
      return;
    }
    if (widget.viewModel.isComplete != oldWidget.viewModel.isComplete) {
      _isComplete = widget.viewModel.isComplete;
    }
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
      if (widget.hideCompleted && newComplete && !_isRecurring) {
        _isAnimating = true;
      }
    });
    try {
      if (widget.onCompletionChange != null) {
        await widget.onCompletionChange!(newComplete);
      } else {
        widget.viewModel.setComplete?.call(newComplete);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isComplete = previousValue;
          _isAnimating = false;
        });
      }
      rethrow;
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
    if (!_isRecurring || !_isComplete || !mounted) return;
    setState(() => _isComplete = false);
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
                      padding: EdgeInsets.only(top: checkboxTopInset),
                      child: AppTaskCheckbox(
                        size: 20,
                        value: _isComplete,
                        accentColor: taskColor,
                        inactiveColor: colorScheme.outline,
                        shape: AppTaskCheckboxShape.rounded,
                        onCheckAnimationCompleted:
                            !widget.isReadOnly && _isRecurring
                            ? _onCheckAnimationCompleted
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
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
                    inlineWidgetBuilders: widget.viewModel.inlineWidgetBuilders,
                    textSelection: widget.viewModel.selection,
                    selectionColor: widget.viewModel.selectionColor,
                    highlightWhenEmpty: widget.viewModel.highlightWhenEmpty,
                    underlines: widget.viewModel.createUnderlines(),
                  ),
                  if (widget.taskMetadata?.scheduleAnchor != null ||
                      widget.taskMetadata?.recurrence != null ||
                      widget.taskMetadata?.reminder != null) ...[
                    const SizedBox(height: 4),
                    TaskMetadataBadges(
                      dueDate: widget.taskMetadata?.scheduleAnchor,
                      recurrence: widget.taskMetadata?.recurrence,
                      hasReminder: widget.taskMetadata?.reminder != null,
                      hasTime: widget.taskMetadata?.hasTime ?? false,
                      completions: widget.taskMetadata?.completions ?? const {},
                      // A recurring checkbox is only an occurrence animation.
                      // Its metadata badge must keep resolving the next
                      // occurrence from the document completion map.
                      isCompleted: _isComplete && !_isRecurring,
                    ),
                    const SizedBox(height: 4),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return TaskExitAnimator(
      hideCompleted: widget.hideCompleted && !_isRecurring,
      isComplete: _isComplete,
      onAnimationComplete: _isAnimating
          ? () => setState(() => _isAnimating = false)
          : null,
      child: ExcludeSemantics(
        excluding: _isHidden,
        child: IgnorePointer(
          ignoring: _isHidden,
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: content,
          ),
        ),
      ),
    );
  }
}

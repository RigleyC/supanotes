import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/presentation/widgets/task_exit_animator.dart';
import 'package:supanotes/features/notes/presentation/widgets/task_text_style_resolver.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_badges.dart';
import 'package:supanotes/shared/theme/app_colors.dart';
import 'package:supanotes/shared/widgets/app_task_checkbox.dart';

const double _taskCheckboxGap = 0.0;
const double _taskCheckboxTouchTarget = 44.0;

class CustomTaskComponentBuilder implements ComponentBuilder {
  CustomTaskComponentBuilder({
    this.editor,
    this.composer,
    this.taskMetadataById = const {},
    this.hideCompleted = false,
    this.onTaskLongPress,
    this.onTaskComplete,
    this.onTaskReopen,
  });

  Editor? editor;

  final MutableDocumentComposer? composer;
  Map<String, TaskModel> taskMetadataById;
  bool hideCompleted;
  ValueChanged<String>? onTaskLongPress;
  final Future<DateTime?> Function(String taskId)? onTaskComplete;
  final Future<void> Function(String taskId)? onTaskReopen;

  final Map<String, Future<void> Function(bool)> _completionHandlers = {};
  final Set<String> _recurringTaskIds = {};

  @override
  TaskComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is! TaskNode) return null;

    final metadata = taskMetadataById[node.id];
    final isRecurring =
        TaskRecurrence.parse(
              node.metadata['recurrenceRule'] as String? ??
                  node.metadata['recurrence'] as String?,
            ) !=
            null ||
        metadata?.recurrence != null;
    if (isRecurring) {
      _recurringTaskIds.add(node.id);
    } else {
      _recurringTaskIds.remove(node.id);
    }

    Future<void> updateCompletion(bool isComplete) async {
      if (isComplete) {
        if (hideCompleted && !isRecurring) {
          FocusManager.instance.primaryFocus?.unfocus();
          composer?.clearSelection();
        }

        await onTaskComplete?.call(node.id);
      } else {
        await onTaskReopen?.call(node.id);
      }
    }

    _completionHandlers[node.id] = updateCompletion;

    return CustomTaskComponentViewModel(
      nodeId: node.id,
      createdAt: node.metadata[NodeMetadata.createdAt],
      padding: EdgeInsets.zero,
      indent: node.indent,
      isComplete: node.isComplete,
      setComplete: (isComplete) => unawaited(updateCompletion(isComplete)),
      text: node.text,
      textDirection: getParagraphDirection(node.text.toPlainText()),
      textAlignment: TextAlign.left,
      textStyleBuilder: noStyleBuilder,
      selectionColor: const Color(0x00000000),
      dueDate: metadata?.dueDate,
      recurrence: metadata?.recurrence,
    );
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is! TaskComponentViewModel) return null;

    final nodeId = componentViewModel.nodeId;

    return CustomTaskComponent(
      key: componentContext.componentKey,
      viewModel: componentViewModel,
      taskMetadata: taskMetadataById[nodeId],
      isRecurring: _recurringTaskIds.contains(nodeId),
      onCompletionChange: _completionHandlers[nodeId],
      hideCompleted: hideCompleted,
      onLongPress: onTaskLongPress == null
          ? null
          : () => onTaskLongPress!(nodeId),
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
    this.dueDate,
    this.recurrence,
  });

  final DateTime? dueDate;
  final TaskRecurrence? recurrence;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CustomTaskComponentViewModel) return false;
    if (super != other) return false;
    return dueDate == other.dueDate && recurrence == other.recurrence;
  }

  @override
  int get hashCode => Object.hash(super.hashCode, dueDate, recurrence);
}

class CustomTaskComponent extends StatefulWidget {
  const CustomTaskComponent({
    super.key,
    required this.viewModel,
    this.isRecurring = false,
    this.taskMetadata,
    this.hideCompleted = false,
    this.onLongPress,
    this.onCompletionChange,
  });

  final TaskComponentViewModel viewModel;
  final bool isRecurring;
  final TaskModel? taskMetadata;
  final bool hideCompleted;
  final VoidCallback? onLongPress;
  final Future<void> Function(bool isComplete)? onCompletionChange;

  @override
  State<CustomTaskComponent> createState() => _CustomTaskComponentState();
}

class _CustomTaskComponentState extends State<CustomTaskComponent>
    with ProxyDocumentComponent<CustomTaskComponent>, ProxyTextComposable {
  final _textKey = GlobalKey();

  late bool _isComplete;
  bool _isAnimating = false;
  bool _isUpdatingCompletion = false;

  bool get _isRecurring => widget.isRecurring;

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
    if (_isUpdatingCompletion) {
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

  void _onCheckAnimationCompleted() {
    if (!_isRecurring || !_isComplete || !mounted) return;
    setState(() => _isComplete = false);
  }

  @override
  GlobalKey<State<StatefulWidget>> get childDocumentComponentKey => _textKey;

  @override
  TextComposable get childTextComposable =>
      childDocumentComponentKey.currentState as TextComposable;

  @override
  Rect getRectForPosition(dynamic nodePosition) {
    try {
      if (!mounted) return Rect.zero;
      final renderObj = _textKey.currentContext?.findRenderObject();
      if (renderObj == null || !renderObj.attached) return Rect.zero;
      return super.getRectForPosition(nodePosition);
    } catch (_) {
      return Rect.zero;
    }
  }

  @override
  Offset getOffsetForPosition(dynamic nodePosition) {
    try {
      if (!mounted) return Offset.zero;
      final renderObj = _textKey.currentContext?.findRenderObject();
      if (renderObj == null || !renderObj.attached) return Offset.zero;
      return super.getOffsetForPosition(nodePosition);
    } catch (_) {
      return Offset.zero;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final semantics = Theme.of(context).extension<AppSemanticColors>();
    final taskColor = semantics?.task ?? AppColors.taskAccent;

    final content = Directionality(
      textDirection: widget.viewModel.textDirection,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: widget.onLongPress,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width:
                  defaultTaskIndentCalculator(
                    widget.viewModel.textStyleBuilder({}),
                    widget.viewModel.indent,
                  ) +
                  _taskCheckboxTouchTarget +
                  _taskCheckboxGap,
              height: _taskCheckboxTouchTarget,
              child: Semantics(
                button: true,
                checked: _isComplete,
                enabled: !_isUpdatingCompletion,
                label: _isComplete
                    ? 'Marcar tarefa como pendente'
                    : 'Concluir tarefa',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _isUpdatingCompletion ? null : _onCheckboxTap,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 11),
                      child: AppTaskCheckbox(
                        value: _isComplete,
                        accentColor: taskColor,
                        inactiveColor: colorScheme.outline,
                        shape: AppTaskCheckboxShape.rounded,
                        onCheckAnimationCompleted: _isRecurring
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
                  if (widget.taskMetadata?.dueDate != null ||
                      widget.taskMetadata?.recurrence != null ||
                      widget.taskMetadata?.reminder != null) ...[
                    const SizedBox(height: 4),
                    TaskMetadataBadges(
                      dueDate: widget.taskMetadata?.dueDate,
                      recurrence: widget.taskMetadata?.recurrence,
                      hasReminder: widget.taskMetadata?.reminder != null,
                      hasTime: widget.taskMetadata?.hasTime ?? false,
                      isCompleted: _isComplete,
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
      child: Padding(padding: const EdgeInsets.only(top: 14), child: content),
    );
  }
}

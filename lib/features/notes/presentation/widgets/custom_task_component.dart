import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/presentation/widgets/task_exit_animator.dart';
import 'package:supanotes/features/notes/presentation/widgets/task_text_style_resolver.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_badges.dart';
import 'package:supanotes/shared/theme/app_colors.dart';
import 'package:supanotes/shared/widgets/app_task_checkbox.dart';

const double _taskCheckboxGap = 9.0;

class CustomTaskComponentBuilder implements ComponentBuilder {
  CustomTaskComponentBuilder({
    this.editor,
    this.composer,
    this.taskMetadataById = const {},
    this.hideCompleted = false,
    this.onTaskLongPress,
    this.onTaskComplete,
    this.onTaskReopen,
    this.animatingNodeIds,
    this.completingTaskIds,
  });

  /// The editor used to issue local [ChangeTaskCompletionRequest]s whenever
  /// the user toggles the checkbox. This is required so the local
  /// [TaskNode] reflects the user's intent immediately, which lets the
  /// [NodeSyncManager] serialize the change to `noteNodes.data` (the
  /// `completed` field) and mark the node as locally dirty so subsequent
  /// streamed (and possibly stale) snapshots don't overwrite it.
  ///
  /// Recurring tasks are exempt: their `completeTask` repo call re-opens
  /// the row with a new `dueDate` (`status='open'`), so emitting a local
  /// completion here would have `NodeSyncManager` overwrite that with
  /// `status='done'`. For those, we rely on the `completingTaskIds`
  /// transient flag instead.
  final Editor? editor;

  final MutableDocumentComposer? composer;
  Map<String, TaskModel> taskMetadataById;
  bool hideCompleted;
  ValueChanged<String>? onTaskLongPress;
  final Future<DateTime?> Function(String taskId)? onTaskComplete;
  final Future<void> Function(String taskId)? onTaskReopen;
  final ValueNotifier<Set<String>>? animatingNodeIds;
  final ValueNotifier<Set<String>>? completingTaskIds;

  void _markAnimating(String nodeId) {
    final current = Set<String>.from(animatingNodeIds?.value ?? const {});
    current.add(nodeId);
    animatingNodeIds?.value = current;
  }

  void _unmarkAnimating(String nodeId) {
    final current = Set<String>.from(animatingNodeIds?.value ?? const {});
    current.remove(nodeId);
    animatingNodeIds?.value = current;
  }

  void _markCompleting(String nodeId) {
    final current = Set<String>.from(completingTaskIds?.value ?? const {});
    current.add(nodeId);
    completingTaskIds?.value = current;
  }

  void _unmarkCompleting(String nodeId) {
    final current = Set<String>.from(completingTaskIds?.value ?? const {});
    current.remove(nodeId);
    completingTaskIds?.value = current;
  }

  @override
  TaskComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is! TaskNode) return null;

    final metadata = taskMetadataById[node.id];

    return CustomTaskComponentViewModel(
      nodeId: node.id,
      createdAt: node.metadata[NodeMetadata.createdAt],
      padding: EdgeInsets.zero,
      indent: node.indent,
      isComplete: (completingTaskIds?.value.contains(node.id) ?? false) || node.isComplete,
      setComplete: (bool isComplete) async {
        final isRecurring = taskMetadataById[node.id]?.recurrence != null;

        final shouldUpdateDoc =
            !isComplete || !isRecurring;
        if (shouldUpdateDoc) {
          editor?.execute([
            ChangeTaskCompletionRequest(
              nodeId: node.id,
              isComplete: isComplete,
            ),
          ]);
        }

        if (isComplete) {
          if (isRecurring) {
            _markCompleting(node.id);
          }

          if (hideCompleted) {
            _markAnimating(node.id);
            FocusManager.instance.primaryFocus?.unfocus();
            composer?.clearSelection();
          }

          try {
            final nextDue = await onTaskComplete?.call(node.id);
            if (nextDue != null && isRecurring) {
              await Future.delayed(const Duration(seconds: 1));
            }
          } finally {
            if (isRecurring) {
              _unmarkCompleting(node.id);
            }
          }
        } else {
          await onTaskReopen?.call(node.id);
        }
      },
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

    if (hideCompleted &&
        componentViewModel.isComplete &&
        !(animatingNodeIds?.value.contains(nodeId) ?? false)) {
      return SizedBox(key: componentContext.componentKey, height: 0);
    }

    return CustomTaskComponent(
      key: componentContext.componentKey,
      viewModel: componentViewModel,
      taskMetadata: taskMetadataById[nodeId],
      hideCompleted: hideCompleted,
      onLongPress: onTaskLongPress == null
          ? null
          : () => onTaskLongPress!(nodeId),
      onAnimationComplete: () {
        _unmarkAnimating(componentViewModel.nodeId);
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
    this.taskMetadata,
    this.hideCompleted = false,
    this.onLongPress,
    this.onAnimationComplete,
  });

  final TaskComponentViewModel viewModel;
  final TaskModel? taskMetadata;
  final bool hideCompleted;
  final VoidCallback? onLongPress;
  final VoidCallback? onAnimationComplete;

  @override
  State<CustomTaskComponent> createState() => _CustomTaskComponentState();
}

class _CustomTaskComponentState extends State<CustomTaskComponent>
    with ProxyDocumentComponent<CustomTaskComponent>, ProxyTextComposable {
  final _textKey = GlobalKey();

  @override
  GlobalKey<State<StatefulWidget>> get childDocumentComponentKey => _textKey;

  @override
  TextComposable get childTextComposable =>
      childDocumentComponentKey.currentState as TextComposable;

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
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: widget.viewModel.setComplete == null
                  ? null
                  : () => widget.viewModel.setComplete!(
                      !widget.viewModel.isComplete,
                    ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: defaultTaskIndentCalculator(
                      widget.viewModel.textStyleBuilder({}),
                      widget.viewModel.indent,
                    ),
                  ),
                  AppTaskCheckbox(
                    value: widget.viewModel.isComplete,
                    accentColor: taskColor,
                    inactiveColor: colorScheme.outline,
                    shape: AppTaskCheckboxShape.rounded,
                  ),
                  const SizedBox(width: _taskCheckboxGap),
                ],
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
                      widget.viewModel.isComplete,
                    ),
                    inlineWidgetBuilders: widget.viewModel.inlineWidgetBuilders,
                    textSelection: widget.viewModel.selection,
                    selectionColor: widget.viewModel.selectionColor,
                    highlightWhenEmpty: widget.viewModel.highlightWhenEmpty,
                    underlines: widget.viewModel.createUnderlines(),
                  ),
                  if (widget.taskMetadata?.dueDate != null ||
                      widget.taskMetadata?.recurrence != null) ...[
                    const SizedBox(height: 4),
                    TaskMetadataBadges(
                      dueDate: widget.taskMetadata?.dueDate,
                      recurrence: widget.taskMetadata?.recurrence,
                      isCompleted: widget.viewModel.isComplete,
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
      hideCompleted: widget.hideCompleted,
      isComplete: widget.viewModel.isComplete,
      onAnimationComplete: widget.onAnimationComplete,
      child: content,
    );
  }
}

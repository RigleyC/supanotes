import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_badges.dart';
import 'package:supanotes/shared/theme/app_colors.dart';
import 'package:supanotes/shared/widgets/animated_task_checkbox.dart';

const double _taskCheckboxSize = 22;
const double _taskCheckboxPadding = 9;
const double _taskCheckboxGap = 9;

/// Renders completed tasks as an empty zero-height box when [hideCompleted]
/// is true, preventing the [UnknownComponentBuilder] Placeholder fallback.
class HiddenTaskComponentBuilder implements ComponentBuilder {
  const HiddenTaskComponentBuilder({this.hideCompleted = false});

  final bool hideCompleted;

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is! TaskNode) return null;
    if (!hideCompleted || !node.isComplete) return null;

    return HiddenTaskComponentViewModel(nodeId: node.id);
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is! HiddenTaskComponentViewModel) return null;

    return SizedBox(key: componentContext.componentKey, height: 0);
  }
}

class HiddenTaskComponentViewModel
    extends SingleColumnLayoutComponentViewModel {
  HiddenTaskComponentViewModel({required super.nodeId})
    : super(createdAt: null, padding: EdgeInsets.zero);

  @override
  HiddenTaskComponentViewModel copy() {
    return HiddenTaskComponentViewModel(nodeId: nodeId);
  }
}

class CustomTaskComponentBuilder implements ComponentBuilder {
  CustomTaskComponentBuilder(
    this._editor, {
    this.taskMetadataById = const {},
    this.hideCompleted = false,
    this.onTaskLongPress,
    this.onTaskComplete,
    this.onTaskReopen,
  });

  final Editor _editor;
  final Map<String, TaskModel> taskMetadataById;
  final bool hideCompleted;
  final ValueChanged<String>? onTaskLongPress;
  final Future<void> Function(String taskId)? onTaskComplete;
  final Future<void> Function(String taskId)? onTaskReopen;
  final Set<String> _pendingResetNodeIds = {};

  @override
  TaskComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is! TaskNode) return null;
    if (hideCompleted && node.isComplete) return null;

    final metadata = taskMetadataById[node.id];

    return CustomTaskComponentViewModel(
      nodeId: node.id,
      createdAt: node.metadata[NodeMetadata.createdAt],
      padding: EdgeInsets.zero,
      indent: node.indent,
      isComplete: node.isComplete,
      setComplete: (bool isComplete) async {
        _editor.execute([
          ChangeTaskCompletionRequest(nodeId: node.id, isComplete: isComplete),
        ]);

        if (isComplete) {
          await onTaskComplete?.call(node.id);
        } else {
          await onTaskReopen?.call(node.id);
        }

        final taskMeta = taskMetadataById[node.id];
        if (isComplete && taskMeta?.recurrence != null) {
          _pendingResetNodeIds.add(node.id);
          Future.delayed(const Duration(milliseconds: 400), () {
            if (!_pendingResetNodeIds.remove(node.id)) return;
            final exists = document.getNodeById(node.id) != null;
            if (exists) {
              _editor.execute([
                ChangeTaskCompletionRequest(nodeId: node.id, isComplete: false),
              ]);
            }
          });
        } else if (!isComplete) {
          // User reopened the task — cancel any pending reset
          _pendingResetNodeIds.remove(node.id);
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

    return CustomTaskComponent(
      key: componentContext.componentKey,
      viewModel: componentViewModel,
      taskMetadata: taskMetadataById[nodeId],
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
    if (super == other) return false;
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
    this.onLongPress,
  });

  final TaskComponentViewModel viewModel;
  final TaskModel? taskMetadata;
  final VoidCallback? onLongPress;

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

    return Directionality(
      textDirection: widget.viewModel.textDirection,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: defaultTaskIndentCalculator(
              widget.viewModel.textStyleBuilder({}),
              widget.viewModel.indent,
            ),
          ),
          _TaskCheckboxHitTarget(
            value: widget.viewModel.isComplete,
            activeColor: taskColor,
            inactiveColor: colorScheme.outline,
            checkmarkColor: Colors.white,
            onChanged: widget.viewModel.setComplete,
            onLongPress: widget.onLongPress,
            firstLineHeight: _firstLineHeight(context),
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
                  textStyleBuilder: (attributions) =>
                      _computeStyles(attributions, context),
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
    );
  }

  TextStyle _computeStyles(
    Set<Attribution> attributions,
    BuildContext context,
  ) {
    final style = widget.viewModel.textStyleBuilder(attributions);
    final baseColor = style.color ?? Theme.of(context).colorScheme.onSurface;
    final muted = baseColor.withValues(
      alpha: widget.viewModel.isComplete ? 0.5 : 1.0,
    );
    return widget.viewModel.isComplete
        ? style.copyWith(decoration: TextDecoration.lineThrough, color: muted)
        : style.copyWith(color: baseColor);
  }

  double _firstLineHeight(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: ' ', style: _computeStyles({}, context)),
      textDirection: widget.viewModel.textDirection,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.preferredLineHeight;
  }
}

class _TaskCheckboxHitTarget extends StatelessWidget {
  const _TaskCheckboxHitTarget({
    required this.value,
    required this.activeColor,
    required this.inactiveColor,
    required this.checkmarkColor,
    required this.onChanged,
    required this.onLongPress,
    required this.firstLineHeight,
  });

  final bool value;
  final Color activeColor;
  final Color inactiveColor;
  final Color checkmarkColor;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onLongPress;
  final double firstLineHeight;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      onLongPress: onLongPress,
      child: SizedBox(
        width: _taskCheckboxPadding + _taskCheckboxSize + _taskCheckboxGap,
        height: (_taskCheckboxPadding * 2) + _taskCheckboxSize,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: _taskCheckboxPadding,
              top: (firstLineHeight - _taskCheckboxSize) / 2,
              child: AnimatedTaskCheckbox(
                size: _taskCheckboxSize,
                value: value,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                checkmarkColor: checkmarkColor,
                onChanged: onChanged,
                onLongPress: onLongPress,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

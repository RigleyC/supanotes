import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_badges.dart';
import 'package:supanotes/shared/theme/app_colors.dart';
import 'package:supanotes/shared/widgets/animated_task_checkbox.dart';

class CustomTaskComponentBuilder implements ComponentBuilder {
  CustomTaskComponentBuilder(
    this._editor, {
    this.taskMetadataById = const {},
    this.hideCompleted = false,
    this.onTaskLongPress,
  });

  final Editor _editor;
  final Map<String, TaskModel> taskMetadataById;
  final bool hideCompleted;
  final ValueChanged<String>? onTaskLongPress;

  @override
  TaskComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is! TaskNode) return null;
    if (hideCompleted && node.isComplete) return null;

    return TaskComponentViewModel(
      nodeId: node.id,
      createdAt: node.metadata[NodeMetadata.createdAt],
      padding: EdgeInsets.zero,
      indent: node.indent,
      isComplete: node.isComplete,
      setComplete: (bool isComplete) {
        _editor.execute([
          ChangeTaskCompletionRequest(nodeId: node.id, isComplete: isComplete),
        ]);
      },
      text: node.text,
      textDirection: getParagraphDirection(node.text.toPlainText()),
      textAlignment: TextAlign.left,
      textStyleBuilder: noStyleBuilder,
      selectionColor: const Color(0x00000000),
    );
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is! TaskComponentViewModel) return null;

    return CustomTaskComponent(
      key: componentContext.componentKey,
      viewModel: componentViewModel,
      taskMetadata: taskMetadataById[componentViewModel.nodeId],
      onLongPress: onTaskLongPress == null
          ? null
          : () => onTaskLongPress!(componentViewModel.nodeId),
    );
  }
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
    const checkboxSize = 22.0;

    return Directionality(
      textDirection: widget.viewModel.textDirection,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: defaultTaskIndentCalculator(
              widget.viewModel.textStyleBuilder({}),
              widget.viewModel.indent,
            ),
          ),
          AnimatedTaskCheckbox(
            size: checkboxSize,
            value: widget.viewModel.isComplete,
            activeColor: taskColor,
            inactiveColor: colorScheme.outline,
            checkmarkColor: Colors.white,
            onChanged: widget.viewModel.setComplete,
            onLongPress: widget.onLongPress,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2, right: 12),
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
                    inlineWidgetBuilders:
                        widget.viewModel.inlineWidgetBuilders,
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
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _computeStyles(Set<Attribution> attributions, BuildContext context) {
    final style = widget.viewModel.textStyleBuilder(attributions);
    final baseColor = style.color ?? Theme.of(context).colorScheme.onSurface;
    final muted =
        baseColor.withValues(alpha: widget.viewModel.isComplete ? 0.5 : 1.0);
    return widget.viewModel.isComplete
        ? style.copyWith(decoration: TextDecoration.lineThrough, color: muted)
        : style.copyWith(color: baseColor);
  }
}

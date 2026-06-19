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

const Duration _exitAnimationDelay = Duration(milliseconds: 300);
const Duration _exitAnimationDuration = Duration(milliseconds: 350);
const Duration _recurrenceResetDelay = Duration(milliseconds: 400);

class CustomTaskComponentBuilder implements ComponentBuilder {
  CustomTaskComponentBuilder(
    this._editor, {
    this.taskMetadataById = const {},
    this.hideCompleted = false,
    this.onTaskLongPress,
    this.onTaskComplete,
    this.onTaskReopen,
    this.requestRebuild,
  });

  final Editor _editor;
  Map<String, TaskModel> taskMetadataById;
  bool hideCompleted;
  ValueChanged<String>? onTaskLongPress;
  final Future<void> Function(String taskId)? onTaskComplete;
  final Future<void> Function(String taskId)? onTaskReopen;
  final VoidCallback? requestRebuild;
  final Set<String> _pendingResetNodeIds = {};
  final Set<String> _animatingNodeIds = {};

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
      isComplete: node.isComplete,
      setComplete: (bool isComplete) async {
        if (isComplete && hideCompleted) {
          _animatingNodeIds.add(node.id);
        }
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
          Future.delayed(_recurrenceResetDelay, () {
            if (!_pendingResetNodeIds.remove(node.id)) return;
            final exists = document.getNodeById(node.id) != null;
            if (exists) {
              try {
                _editor.execute([
                  ChangeTaskCompletionRequest(nodeId: node.id, isComplete: false),
                ]);
              } catch (_) {
                // Editor was disposed while the timer was pending — safe to ignore.
              }
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

    if (hideCompleted && componentViewModel.isComplete && !_animatingNodeIds.contains(nodeId)) {
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
        _animatingNodeIds.remove(componentViewModel.nodeId);
        requestRebuild?.call();
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
    with ProxyDocumentComponent<CustomTaskComponent>, ProxyTextComposable, TickerProviderStateMixin {
  final _textKey = GlobalKey();

  late AnimationController _exitController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _sizeAnimation;

  @override
  void initState() {
    super.initState();
    _exitController = AnimationController(
      vsync: this,
      duration: _exitAnimationDuration,
    );
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeOut),
    );
    _sizeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeInOutCubic),
    );
    _exitController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onAnimationComplete?.call();
      }
    });
  }

  @override
  void dispose() {
    _exitController.dispose();
    super.dispose();
  }

  @override
  GlobalKey<State<StatefulWidget>> get childDocumentComponentKey => _textKey;

  @override
  TextComposable get childTextComposable =>
      childDocumentComponentKey.currentState as TextComposable;

  @override
  void didUpdateWidget(CustomTaskComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hideCompleted && widget.viewModel.isComplete && !oldWidget.viewModel.isComplete) {
      Future.delayed(_exitAnimationDelay, () {
        if (mounted) {
          _exitController.forward();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final semantics = Theme.of(context).extension<AppSemanticColors>();
    final taskColor = semantics?.task ?? AppColors.taskAccent;

    final content = Directionality(
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

    return SizeTransition(
      sizeFactor: _sizeAnimation,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: content,
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

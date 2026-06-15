import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_badges.dart';
import 'package:supanotes/shared/theme/app_colors.dart';

class CustomTaskComponentBuilder implements ComponentBuilder {
  CustomTaskComponentBuilder(
    this._editor, {
    this.taskMetadataById = const {},
    this.focusNode,
    this.onTaskLongPress,
  });

  final Editor _editor;
  final FocusNode? focusNode;
  final Map<String, TaskModel> taskMetadataById;
  final ValueChanged<String>? onTaskLongPress;

  @override
  TaskComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is! TaskNode) return null;

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
      editor: _editor,
      focusNode: focusNode,
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
    this.editor,
    this.focusNode,
    required this.viewModel,
    this.taskMetadata,
    this.onLongPress,
  });

  final Editor? editor;
  final FocusNode? focusNode;
  final TaskComponentViewModel viewModel;
  final TaskModel? taskMetadata;
  final VoidCallback? onLongPress;

  @override
  State<CustomTaskComponent> createState() => _CustomTaskComponentState();
}

class _CustomTaskComponentState extends State<CustomTaskComponent>
    with ProxyDocumentComponent<CustomTaskComponent>, ProxyTextComposable {
  static const _longPressDelay = Duration(milliseconds: 500);
  static const _tapSlop = 8.0;

  final _checkboxKey = GlobalKey();
  final _textKey = GlobalKey();
  late bool _isComplete;
  Timer? _longPressTimer;
  Offset? _pointerDownPosition;
  bool _didLongPress = false;

  @override
  void initState() {
    super.initState();
    _isComplete = widget.viewModel.isComplete;
  }

  @override
  void didUpdateWidget(CustomTaskComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.viewModel.isComplete != oldWidget.viewModel.isComplete) {
      setState(() => _isComplete = widget.viewModel.isComplete);
    }
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  @override
  GlobalKey<State<StatefulWidget>> get childDocumentComponentKey => _textKey;

  @override
  TextComposable get childTextComposable =>
      childDocumentComponentKey.currentState as TextComposable;

  TextStyle _computeStyles(Set<Attribution> attributions) {
    final style = widget.viewModel.textStyleBuilder(attributions);
    final baseColor = style.color ?? Theme.of(context).colorScheme.onSurface;
    final muted = baseColor.withValues(alpha: _isComplete ? 0.5 : 1.0);
    return _isComplete
        ? style.copyWith(decoration: TextDecoration.lineThrough, color: muted)
        : style.copyWith(color: baseColor);
  }

  void _onToggle() {
    widget.viewModel.setComplete?.call(!_isComplete);
  }

  void _placeCaretAt(Offset globalOffset) {
    final editor = widget.editor;
    final textContext = _textKey.currentContext;
    if (editor == null || textContext == null) return;

    final textBox = textContext.findRenderObject() as RenderBox?;
    if (textBox == null || !textBox.hasSize) return;

    final textComponent = childTextComposable as DocumentComponent;
    final nodePosition = textComponent.getPositionAtOffset(
      textBox.globalToLocal(globalOffset),
    );
    if (nodePosition == null) return;

    widget.focusNode?.requestFocus();
    editor.execute([
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: widget.viewModel.nodeId,
            nodePosition: nodePosition,
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
    ]);
  }

  bool _isOverCheckbox(Offset globalOffset) {
    final checkboxContext = _checkboxKey.currentContext;
    final checkboxBox = checkboxContext?.findRenderObject() as RenderBox?;
    if (checkboxBox == null || !checkboxBox.hasSize) return false;

    final localOffset = checkboxBox.globalToLocal(globalOffset);
    return (Offset.zero & checkboxBox.size).contains(localOffset);
  }

  void _onPointerDown(PointerDownEvent event) {
    _didLongPress = false;
    _pointerDownPosition = event.position;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(_longPressDelay, () {
      _didLongPress = true;
      widget.onLongPress?.call();
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    final downPosition = _pointerDownPosition;
    if (downPosition == null) return;

    if ((event.position - downPosition).distance > _tapSlop) {
      _longPressTimer?.cancel();
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _longPressTimer?.cancel();
    final downPosition = _pointerDownPosition;
    _pointerDownPosition = null;
    if (_didLongPress ||
        downPosition == null ||
        (event.position - downPosition).distance > _tapSlop ||
        _isOverCheckbox(event.position)) {
      return;
    }

    _placeCaretAt(event.position);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _longPressTimer?.cancel();
    _pointerDownPosition = null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final semantics = Theme.of(context).extension<AppSemanticColors>();
    final taskColor = semantics?.task ?? AppColors.taskAccent;
    const checkboxSize = 22.0;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: widget.onLongPress == null ? null : _onPointerCancel,
      child: Directionality(
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
            _AnimatedTaskCheckbox(
              key: _checkboxKey,
              size: checkboxSize,
              value: _isComplete,
              activeColor: taskColor,
              inactiveColor: colorScheme.outline,
              checkmarkColor: Colors.white,
              onChanged: widget.viewModel.setComplete != null
                  ? (_) => _onToggle()
                  : null,
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onLongPress: widget.onLongPress,
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
                        textStyleBuilder: _computeStyles,
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
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedTaskCheckbox extends StatefulWidget {
  const _AnimatedTaskCheckbox({
    super.key,
    required this.size,
    required this.value,
    required this.activeColor,
    required this.inactiveColor,
    required this.checkmarkColor,
    required this.onChanged,
  });

  final double size;
  final bool value;
  final Color activeColor;
  final Color inactiveColor;
  final Color checkmarkColor;
  final void Function(bool)? onChanged;

  @override
  State<_AnimatedTaskCheckbox> createState() => _AnimatedTaskCheckboxState();
}

class _AnimatedTaskCheckboxState extends State<_AnimatedTaskCheckbox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _checkAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnim = CurvedAnimation(
      parent: _controller,
      curve: const ElasticOutCurve(0.8),
    );

    _checkAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 0.7, curve: Curves.easeOut),
    );

    if (widget.value) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(_AnimatedTaskCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      if (widget.value) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;

    return InkWell(
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      onTap: widget.onChanged != null
          ? () => widget.onChanged!(!widget.value)
          : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: SizedBox(
          width: size,
          height: size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final scale = 1.0 - (0.15 * (1.0 - _scaleAnim.value));
              final checkProgress = _checkAnim.value;

              return Transform.scale(
                scale: scale,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: widget.value
                        ? widget.activeColor
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: widget.value
                          ? widget.activeColor
                          : widget.inactiveColor,
                      width: 2,
                    ),
                  ),
                  child: _CheckmarkPainter(
                    progress: checkProgress,
                    color: widget.checkmarkColor,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CheckmarkPainter extends StatelessWidget {
  const _CheckmarkPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CheckmarkPaint(progress: progress, color: color),
    );
  }
}

class _CheckmarkPaint extends CustomPainter {
  _CheckmarkPaint({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    final start = Offset(size.width * 0.22, size.height * 0.52);
    final mid = Offset(size.width * 0.45, size.height * 0.72);
    final end = Offset(size.width * 0.78, size.height * 0.30);

    path.moveTo(start.dx, start.dy);
    path.lineTo(mid.dx, mid.dy);
    path.lineTo(end.dx, end.dy);

    // Guard: progress == 0 means fully unchecked. With StrokeCap.round,
    // extractPath(0, 0) would render a tiny dot at the start point — skip.
    if (progress <= 0.0) return;

    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      final extractPath = metric.extractPath(0.0, metric.length * progress);
      canvas.drawPath(extractPath, paint);
    }
  }

  @override
  bool shouldRepaint(_CheckmarkPaint oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

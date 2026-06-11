import 'package:flutter/material.dart';

class PullDownBriefPanel extends StatefulWidget {
  const PullDownBriefPanel({
    super.key,
    required this.background,
    required this.builder,
    this.onProgressChanged,
  });

  final Widget background;
  final Widget Function(BuildContext context, ScrollController controller)
  builder;
  final ValueChanged<double>? onProgressChanged;

  static const double _briefRevealHeight = 180;
  static const double _openSize = 1.0;
  static const double _cornerRadius = 30;

  @override
  State<PullDownBriefPanel> createState() => _PullDownBriefPanelState();
}

class _PullDownBriefPanelState extends State<PullDownBriefPanel> {
  late final DraggableScrollableController _controller;
  double _closedSize = 0;
  double _revealProgress = 0;
  double _height = 0;
  double? _lastPointerY;

  @override
  void initState() {
    super.initState();
    _controller = DraggableScrollableController()..addListener(_notifyProgress);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_notifyProgress)
      ..dispose();
    super.dispose();
  }

  void _notifyProgress() {
    if (_closedSize == 0 || !_controller.isAttached) return;
    final progress =
        ((PullDownBriefPanel._openSize - _controller.size) /
                (PullDownBriefPanel._openSize - _closedSize))
            .clamp(0.0, 1.0);
    if (progress != _revealProgress) {
      setState(() => _revealProgress = progress);
    }
    widget.onProgressChanged?.call(progress);
  }

  void _onPointerMove(PointerMoveEvent event) {
    final lastPointerY = _lastPointerY;
    if (lastPointerY == null ||
        _height == 0 ||
        _revealProgress <= 0 ||
        !_controller.isAttached) {
      _lastPointerY = event.position.dy;
      return;
    }

    final deltaY = event.position.dy - lastPointerY;
    _lastPointerY = event.position.dy;
    if (deltaY >= 0) return;

    final nextSize = (_controller.size - deltaY / _height).clamp(
      _closedSize,
      PullDownBriefPanel._openSize,
    );
    _controller.jumpTo(nextSize);
  }

  void _settleFromPointer() {
    _lastPointerY = null;
    if (_closedSize == 0 || !_controller.isAttached) return;
    final midpoint = (_closedSize + PullDownBriefPanel._openSize) / 2;
    final target = _controller.size <= midpoint
        ? _closedSize
        : PullDownBriefPanel._openSize;
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _height = constraints.maxHeight;
        final closedSize =
            ((constraints.maxHeight - PullDownBriefPanel._briefRevealHeight) /
                    constraints.maxHeight)
                .clamp(0.0, 1.0);
        if (_closedSize != closedSize) {
          _closedSize = closedSize;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            widget.onProgressChanged?.call(0);
          });
        }

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            const Positioned.fill(child: ColoredBox(color: Colors.black)),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: PullDownBriefPanel._briefRevealHeight,
              child: widget.background,
            ),
            Listener(
              onPointerDown: (event) => _lastPointerY = event.position.dy,
              onPointerMove: _onPointerMove,
              onPointerUp: (_) => _settleFromPointer(),
              onPointerCancel: (_) => _settleFromPointer(),
              child: DraggableScrollableSheet(
                controller: _controller,
                snap: true,
                snapSizes: [closedSize, PullDownBriefPanel._openSize],
                initialChildSize: PullDownBriefPanel._openSize,
                minChildSize: closedSize,
                maxChildSize: PullDownBriefPanel._openSize,
                builder: (context, scrollController) {
                  return Material(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(
                        PullDownBriefPanel._cornerRadius * _revealProgress,
                      ),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: widget.builder(context, scrollController),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

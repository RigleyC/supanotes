import 'package:cue/cue.dart';
import 'package:flutter/material.dart';

import 'daily_brief_panel.dart';

class PullDownBriefPanel extends StatefulWidget {
  const PullDownBriefPanel({
    super.key,
    required this.child,
    this.onOpenChanged,
  });

  final Widget child;
  final ValueChanged<bool>? onOpenChanged;

  static const double _kBriefMaxHeight = 180;
  static const double _kSettleThreshold = 72;

  @override
  State<PullDownBriefPanel> createState() => _PullDownBriefPanelState();
}

class _PullDownBriefPanelState extends State<PullDownBriefPanel>
    with TickerProviderStateMixin {
  late final CueController _controller;
  CueAnimation<double>? _offsetAnimation;
  double _offset = 0;
  double? _lastPointerY;
  bool _isScrollAtTop = true;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = CueController(
      vsync: this,
      motion: Spring.bouncy(),
      debugLabel: 'pullDownBriefPanel',
    );
  }

  @override
  void dispose() {
    _offsetAnimation?.release();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: PullDownBriefPanel._kBriefMaxHeight,
          child: DailyBriefPanel(),
        ),
        Listener(
          onPointerDown: (event) {
            _controller.stop();
            _lastPointerY = event.position.dy;
          },
          onPointerMove: (event) {
            final lastPointerY = _lastPointerY;
            if (lastPointerY == null) return;

            final delta = event.position.dy - lastPointerY;
            _lastPointerY = event.position.dy;

            if (!_isScrollAtTop && _offset <= 0) return;
            if (_offset <= 0 && delta < 0) return;

            setState(() {
              _offset = (_offset + delta).clamp(
                0.0,
                PullDownBriefPanel._kBriefMaxHeight,
              );
            });
          },
          onPointerUp: (_) => _settle(),
          onPointerCancel: (_) => _settle(),
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              final metrics = notification.metrics;
              _isScrollAtTop = metrics.pixels <= metrics.minScrollExtent + 0.5;
              return false;
            },
            child: Transform.translate(
              offset: Offset(0, _offset),
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: _offset > 0
                    ? const BorderRadius.vertical(top: Radius.circular(30))
                    : BorderRadius.zero,
                shadowColor: Colors.red,
                child: widget.child,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _settle() {
    _lastPointerY = null;
    final target = _offset >= PullDownBriefPanel._kSettleThreshold
        ? PullDownBriefPanel._kBriefMaxHeight
        : 0.0;
    _notifyOpen(target >= PullDownBriefPanel._kBriefMaxHeight);
    _animateTo(target);
  }

  void _notifyOpen(bool open) {
    if (open != _isOpen) {
      _isOpen = open;
      widget.onOpenChanged?.call(open);
    }
  }

  void _animateTo(double target) {
    final old = _offsetAnimation;
    _offsetAnimation = _controller.tweenTrack<double>(
      from: _offset,
      to: target,
    )..addListener(() {
      setState(() => _offset = _offsetAnimation!.value);
    });
    old?.release();
    _controller
      ..stop()
      ..forward(from: 0.0);
  }
}

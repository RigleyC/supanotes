import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// Wraps [child] in the app's pressed-scale motion.
///
/// The pressed scale is applied instantly on [pressed] so even a quick tap
/// shows the press effect, and the release springs back to full size. Without
/// the instant jump a fast tap would interrupt the press-in animation before
/// it became visible.
class AppPressScale extends StatefulWidget {
  const AppPressScale({
    super.key,
    required this.pressed,
    required this.child,
  });

  /// Whether the widget is currently pressed. Pass `false` when not
  /// interactive.
  final bool pressed;

  /// The widget to scale.
  final Widget child;

  @override
  State<AppPressScale> createState() => _AppPressScaleState();
}

class _AppPressScaleState extends State<AppPressScale>
    with SingleTickerProviderStateMixin {
  static const double _pressedScale = 0.96;
  static const Motion _releaseMotion =
      Motion.cupertino(duration: Duration(milliseconds: 180));

  late final SingleMotionController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SingleMotionController(
      motion: _releaseMotion,
      vsync: this,
      initialValue: widget.pressed ? _pressedScale : 1,
    )..addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant AppPressScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pressed == oldWidget.pressed) return;
    if (widget.pressed) {
      _controller.value = _pressedScale;
    } else {
      _controller.animateTo(1);
    }
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Transform.scale(scale: _controller.value, child: widget.child);
  }
}
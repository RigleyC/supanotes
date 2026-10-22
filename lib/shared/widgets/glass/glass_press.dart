// The press values come from liquid_glass_widgets 1.13.0 (MIT, Sebastian
// Degenaar), measured on iOS 26/27 glass buttons: `LiquidStretch` and
// `AnchorStretchSettings.nativeTremor` in src/engine/stretch.dart, and the
// ambient base light of `GlassButton`.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:motor/motor.dart';
import 'package:supanotes/shared/widgets/glass/listenable_transform.dart';
import 'package:supanotes/shared/widgets/glass/spring_retarget.dart';

/// Gives glass the press of an iOS 26 button. While the finger is down, the
/// glass inflates by [growth] points along its longest side, leans a little
/// toward the finger, and its surface brightens evenly ([GlassPressLight]).
/// On release it springs back through rest with one small undershoot.
///
/// Wrap the glass shape, so the glass itself inflates, and put a
/// [GlassPressLight] inside it, under the content. It reads raw pointers, so
/// it never competes with the tap or drag gestures around it.
class GlassPress extends StatefulWidget {
  const GlassPress({
    required this.child,
    super.key,
    this.enabled = true,
    this.growth = nativeGrowth,
  });

  /// How much a native iOS 26 button grows along its longest side.
  static const double nativeGrowth = 17;

  final bool enabled;

  /// Growth in points along the longest side at full press.
  final double growth;
  final Widget child;

  @override
  State<GlassPress> createState() => _GlassPressState();
}

class _GlassPressState extends State<GlassPress> with TickerProviderStateMixin {
  /// Reaches the full size in about 150 ms with a small overshoot.
  static const _pressIn = CupertinoMotion.snappy(
    duration: Duration(milliseconds: 250),
    extraBounce: .1,
  );

  /// Back through rest in under 100 ms, then one clean undershoot.
  static const _pressOut = CupertinoMotion.bouncy(
    duration: Duration(milliseconds: 280),
    extraBounce: .15,
  );

  static const _lean = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 150),
  );
  static const _leanBack = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 250),
  );

  /// The native tremor: at most about 5% of elongation toward the finger,
  /// matching squash across, and a few points of travel.
  static const _resistance = .01;
  static const _elongation = .1;
  static const _squash = .1;
  static const _travel = .1;

  late final _press = SingleMotionController(motion: _pressIn, vsync: this);
  late final _drag = MotionController<Offset>(
    motion: _lean,
    vsync: this,
    converter: const OffsetMotionConverter(),
    initialValue: Offset.zero,
  );
  late final _transform = Listenable.merge([_press, _drag]);

  int? _pointer;
  Offset _origin = Offset.zero;

  @override
  void didUpdateWidget(GlassPress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _pointer != null) _release();
  }

  @override
  void dispose() {
    _press.dispose();
    _drag.dispose();
    super.dispose();
  }

  void _onDown(PointerDownEvent event) {
    if (!widget.enabled || _pointer != null) return;
    _pointer = event.pointer;
    _origin = event.localPosition;
    springTo(_press, _pressIn, 1.0);
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    springTo(
      _drag,
      _lean,
      (event.localPosition - _origin).withResistance(_resistance),
    );
  }

  void _onEnd(PointerEvent event) {
    if (event.pointer == _pointer) _release();
  }

  void _release() {
    _pointer = null;
    springTo(_press, _pressOut, 0.0);
    springTo(_drag, _leanBack, Offset.zero);
  }

  Matrix4 _matrix(Size size) {
    if (size.isEmpty) return Matrix4.identity();
    final longest = size.longestSide;
    final press = 1 + _press.value * widget.growth / longest;
    final drag = _drag.value;
    final ex = _elongation * drag.dx.abs() / size.width;
    final ey = _elongation * drag.dy.abs() / size.height;
    final sx = press * (1 + ex - _squash * ey);
    final sy = press * (1 + ey - _squash * ex);
    final center = size.center(Offset.zero) + drag * _travel;
    return Matrix4.translationValues(center.dx, center.dy, 0)
      ..scaleByDouble(sx, sy, 1, 1)
      ..translateByDouble(-size.width / 2, -size.height / 2, 0, 1);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onEnd,
      onPointerCancel: _onEnd,
      child: _GlassPressScope(
        press: _press,
        child: ListenableTransform(
          listenable: _transform,
          transform: _matrix,
          child: widget.child,
        ),
      ),
    );
  }
}

class _GlassPressScope extends InheritedWidget {
  const _GlassPressScope({required this.press, required super.child});

  final ValueListenable<double> press;

  static ValueListenable<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GlassPressScope>()?.press;

  @override
  bool updateShouldNotify(_GlassPressScope oldWidget) =>
      press != oldWidget.press;
}

/// The even brightening of pressed iOS 26 glass, painted under [child] so
/// the icon or label stays crisp. Place it inside the glass of a
/// [GlassPress]; elsewhere it just shows [child].
class GlassPressLight extends StatelessWidget {
  const GlassPressLight({required this.child, super.key});

  /// About +15 luma over light glass. Dark glass gets half, where the same
  /// overlay reads as a flash.
  static const double _light = .3;
  static const double _dark = .14;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final press = _GlassPressScope.maybeOf(context);
    if (press == null) return child;
    final strength = Theme.of(context).brightness == Brightness.dark
        ? _dark
        : _light;
    return CustomPaint(
      painter: _PressLightPainter(press, strength),
      child: child,
    );
  }
}

class _PressLightPainter extends CustomPainter {
  _PressLightPainter(this.press, this.strength) : super(repaint: press);

  final ValueListenable<double> press;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final alpha = strength * press.value.clamp(0.0, 1.0);
    if (alpha == 0) return;
    // Every pressable glass in the app is a circle or a pill.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.shortestSide / 2),
      ),
      Paint()..color = Colors.white.withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(_PressLightPainter oldDelegate) =>
      oldDelegate.press != press || oldDelegate.strength != strength;
}

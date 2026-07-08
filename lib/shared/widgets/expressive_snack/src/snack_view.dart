import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:material_shapes/material_shapes.dart';
import 'package:motor/motor.dart';
import 'snack.dart';
import 'snack_overlay.dart';

class SnackView extends StatefulWidget {
  const SnackView({super.key, required this.snack, required this.depth});

  final Snack snack;
  final int depth;

  @override
  State<SnackView> createState() => SnackViewState();
}

class SnackViewState extends State<SnackView> with TickerProviderStateMixin {
  static const double _travel = 160;
  static const double _dismissOffset = 24;
  static const double _dismissVelocity = 300;
  static const double _peek = 12;
  static const double _shrink = 0.05;
  static const double _shade = 0.15;
  static const double _shakeVelocity = 600;

  late final AnimationController _drag = AnimationController.unbounded(
    vsync: this,
  )..value = 0;

  late final AnimationController _shake = AnimationController.unbounded(
    vsync: this,
  )..value = 0;

  bool _visible = false;
  bool _removing = false;
  Timer? _timer;

  bool get isDismissing => _removing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
    _timer = Timer(widget.snack.duration, dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _drag.dispose();
    _shake.dispose();
    super.dispose();
  }

  void dismiss() {
    if (_removing) return;
    _removing = true;
    _timer?.cancel();
    _drag.stop();
    if (mounted) setState(() => _visible = false);
    SnackOverlay.refresh();
    Timer(const Duration(milliseconds: 450), () {
      SnackOverlay.remove(widget.snack);
    });
  }

  void shake() {
    if (_removing) return;
    _timer?.cancel();
    _timer = Timer(widget.snack.duration, dismiss);
    const spring = SpringDescription(mass: 1, stiffness: 400, damping: 10);
    _shake.animateWith(
      SpringSimulation(spring, _shake.value, 0, _shakeVelocity),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final styles = theme.textTheme;

    final background = colors.inverseSurface;
    final foreground = colors.onInverseSurface;
    final hasIcon = widget.snack.icon != null;

    final pill = Material(
      color: background,
      shape: const StadiumBorder(),
      elevation: 6,
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasIcon)
              Padding(
                padding: const EdgeInsets.all(6),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Material(
                    color: colors.primary,
                    shape: const MaterialShapeBorder(
                      shape: MaterialShape(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(99),
                          topRight: Radius.circular(99),
                        ),
                      ),
                    ),
                    child: Icon(
                      widget.snack.icon,
                      color: colors.onPrimary,
                      size: 20,
                    ),
                  ),
                ),
              ),
            Flexible(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  hasIcon ? 6 : 24,
                  14,
                  widget.snack.action != null ? 8 : 24,
                  14,
                ),
                child: Text(
                  widget.snack.message,
                  style: styles.bodyMedium?.copyWith(color: foreground),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (widget.snack.action != null) ...[
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton(
                  onPressed: () {
                    widget.snack.action!.onPressed();
                    dismiss();
                  },
                  child: Text(
                    widget.snack.action!.label,
                    style: TextStyle(color: colors.primary),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    final depth = widget.depth;
    final scale = 1.0 - (depth * _shrink);
    final translate = depth * _peek;

    const entrySpring = SpringDescription(mass: 1, stiffness: 300, damping: 18);
    const exitSpring = SpringDescription(mass: 1, stiffness: 450, damping: 30);

    return Focus(
      child: Center(
        child: IgnorePointer(
          ignoring: depth > 0,
          child: AnimatedBuilder(
            animation: Listenable.merge([_drag, _shake]),
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(_shake.value, _drag.value - translate),
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.bottomCenter,
                  child: child,
                ),
              );
            },
            child: AnimatedColorAsphalt(
              color: Colors.black.withValues(alpha: depth * _shade),
              child: AnimatedOpacitySpring(
                visible: _visible,
                entrySpring: entrySpring,
                exitSpring: exitSpring,
                child: AnimatedTranslationSpring(
                  visible: _visible,
                  entrySpring: entrySpring,
                  exitSpring: exitSpring,
                  offset: const Offset(0, _travel),
                  child: GestureDetector(
                    onTap: dismiss,
                    onVerticalDragUpdate: (details) {
                      _drag.value += details.primaryDelta!;
                    },
                    onVerticalDragEnd: (details) {
                      final offset = _drag.value;
                      final velocity = details.primaryVelocity!;

                      if (offset > _dismissOffset || velocity > _dismissVelocity) {
                        dismiss();
                        _drag.animateWith(
                          ScrollSpringSimulation(
                            const SpringDescription(
                              mass: 1,
                              stiffness: 450,
                              damping: 30,
                            ),
                            offset,
                            _travel,
                            velocity,
                          ),
                        );
                      } else {
                        const spring = SpringDescription(mass: 1, stiffness: 400, damping: 20);
                        _drag.animateWith(
                          SpringSimulation(spring, offset, 0, velocity),
                        );
                      }
                    },
                    child: pill,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

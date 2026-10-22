import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:supanotes/shared/widgets/glass/glass_press.dart';

/// Liquid glass surface: refraction and tint of what is behind it, with the
/// renderer's own edge light. Each surface owns its layer, so it can sit
/// anywhere in the tree. Wrap screens that show several glass surfaces in a
/// [BackdropGroup] so they share one backdrop copy.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    required this.child,
    super.key,
    this.width,
    this.height,
    this.radius,
    this.circular = false,
    this.interactive = false,
  });

  final double? width;

  /// Fixed height. Null lets the surface grow with the [child].
  final double? height;

  /// Corner radius. Null uses half the height (a pill).
  final double? radius;

  /// Circular corners instead of a superellipse: a square surface is a true
  /// circle and a wider one a pill, so a width animation between the two
  /// stays smooth. A superellipse in a square looks squarish.
  final bool circular;

  /// Presses like an iOS 26 glass button: inflates, leans toward the finger
  /// and brightens ([GlassPress]).
  final bool interactive;

  final Widget child;

  LiquidShape get _shape {
    final corner = radius ?? (height ?? 0) / 2;
    return circular
        ? LiquidRoundedRectangle(borderRadius: corner)
        : LiquidRoundedSuperellipse(borderRadius: corner);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    final glass = LiquidGlassLayer(
      settings: LiquidGlassSettings.ios27Regular(brightness: brightness),
      // Shares one backdrop copy with the other glass on screen through the
      // enclosing BackdropGroup, instead of copying it again for this layer.
      useBackdropGroup: true,
      child: LiquidGlass(
        shape: _shape,
        child: interactive ? GlassPressLight(child: child) : child,
      ),
    );

    return SizedBox(
      width: width,
      height: height,
      // The press transforms the whole layer, so the inflated glass is not
      // cut at the layer's resting bounds.
      child: interactive ? GlassPress(child: glass) : glass,
    );
  }
}

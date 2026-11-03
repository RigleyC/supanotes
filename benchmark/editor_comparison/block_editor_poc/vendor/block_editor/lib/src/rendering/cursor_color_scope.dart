library;

import 'package:flutter/widgets.dart';

/// An [InheritedWidget] that carries the animated cursor color and width
/// down to RichTextRenderer without requiring any parameter threading
/// through BlockPlugin.build.
///
/// Placed in the widget tree by BlockCursor when a cursor should be shown.
/// RichTextRenderer reads from it in build via [maybeOf].
class CursorColorScope extends InheritedWidget {
  /// Creates a [CursorColorScope].
  const CursorColorScope({
    super.key,
    required this.color,
    required this.cursorWidth,
    required super.child,
  });

  /// The animated cursor color. Opacity varies with the blink animation.
  final Color color;

  /// The width of the caret in logical pixels.
  final double cursorWidth;

  /// Returns the nearest [CursorColorScope] ancestor, or null if none exists.
  static CursorColorScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CursorColorScope>();

  @override
  bool updateShouldNotify(CursorColorScope old) =>
      old.color != color || old.cursorWidth != cursorWidth;
}

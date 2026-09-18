import 'package:flutter/widgets.dart';

/// Provides the system inset used by content that sits above the app navbar.
abstract final class NavigationBarInsets {
  /// Adds the device bottom safe-area inset to [base].
  static EdgeInsets scrollPadding(
    BuildContext context, {
    EdgeInsets base = EdgeInsets.zero,
  }) => base.copyWith(
    bottom: base.bottom + MediaQuery.paddingOf(context).bottom,
  );
}

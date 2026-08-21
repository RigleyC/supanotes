/// Spacing and radius constants for the SupaNotes design system.
///
/// All values follow an 8-pt grid (with 4-pt half-steps) to keep vertical and
/// horizontal rhythm consistent across screens.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  static const double buttonHeight = 48;
  static const double tileHeight = 48;
  static const double tileIconSize = 20;
  static const double iconSm = 16;
  static const double iconMd = 24;
  static const double iconLg = 48;
  static const double elevationSm = 1;
  static const double elevationMd = 2;

  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;
  static const double radiusFull = 999;

  /// Height of the iOS 26 native Liquid Glass toolbar (UINavigationBar height).
  /// Used to add top body padding on screens that use AdaptiveScaffold with
  /// an AppBar on iOS 26+, since IOS26Scaffold does not automatically inset
  /// the body below the native toolbar.
  static const double ios26ToolbarHeight = 44;
}

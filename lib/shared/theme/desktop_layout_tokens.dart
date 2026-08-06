import 'dart:math' as math;

/// Layout values shared by the desktop notes shell and its editor surface.
///
/// These values describe the desktop composition only. Content styling stays
/// in the note editor stylesheet and colors stay in [AppColors]/[AppTheme].
class DesktopLayoutTokens {
  DesktopLayoutTokens._();

  static const double sidebarInitialWidth = 240.0;
  static const double sidebarMinWidth = 220.0;
  static const double sidebarMaxWidth = 420.0;
  static const double sidebarCollapsedWidth = 48.0;
  static const double sidebarViewportFraction = 0.35;

  static const double chromeControlHeight = 32.0;
  static const double chromeHeight = 56.0;
  static const double sidebarRowHeight = 32.0;
  static const double sidebarContentPadding = 12.0;
  static const double chromeRadius = 8.0;
  static const double dividerWidth = 1.0;
  static const double resizeHitWidth = 8.0;
  static const double surfaceBlurSigma = 16.0;
  static const double surfaceOpacity = 0.84;

  static const double editorMaxWidth = 734.0;
  static const double editorSidePaddingMin = 24.0;
  static const double editorSidePaddingMax = 64.0;
  static const double editorTopPadding = 144.0;
  static const double editorBottomPaddingFraction = 0.4;

  static double editorBottomPaddingForHeight(double viewportHeight) {
    return viewportHeight * editorBottomPaddingFraction;
  }

  static double maxSidebarWidth(double viewportWidth) {
    return math.max(
      sidebarMinWidth,
      math.min(sidebarMaxWidth, viewportWidth * sidebarViewportFraction),
    );
  }

  static double clampSidebarWidth(
    double width, {
    required double viewportWidth,
  }) {
    return width.clamp(sidebarMinWidth, maxSidebarWidth(viewportWidth));
  }
}

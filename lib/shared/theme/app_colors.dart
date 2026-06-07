import 'package:flutter/material.dart';

/// Color palette for the SupaNotes design system.
///
/// The Material 3 [ColorScheme] is derived from a single seed color via
/// [ColorScheme.fromSeed] so the whole UI is tonally consistent. Semantic
/// colors (success, warning, info, muted) are not part of the Material 3
/// spec and are exposed as raw constants so feature code can reference them
/// without rebuilding a custom [ColorScheme] extension.
///
/// **Seed choice**: `indigo-600` (#4F46E5, a deep violet-blue) — it reads as
/// modern and professional in both light and dark mode, and it stays
/// legible on white surfaces. It is the same family used by apps like
/// Linear and Notion's accent.
class AppColors {
  AppColors._();

  // ---------------------------------------------------------------------------
  // Seed
  // ---------------------------------------------------------------------------

  static const Color primarySeed = Color(0xFF4F46E5);

  // ---------------------------------------------------------------------------
  // Light scheme
  // ---------------------------------------------------------------------------

  static final ColorScheme lightColorScheme = ColorScheme.fromSeed(
    seedColor: primarySeed,
    brightness: Brightness.light,
  );

  // ---------------------------------------------------------------------------
  // Dark scheme
  // ---------------------------------------------------------------------------

  static final ColorScheme darkColorScheme = ColorScheme.fromSeed(
    seedColor: primarySeed,
    brightness: Brightness.dark,
  );

  // ---------------------------------------------------------------------------
  // Semantic colors (intentionally identical across light and dark — they
  // // communicate state, not surface ownership).
  // ---------------------------------------------------------------------------

  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);
  static const Color muted = Color(0xFF6B7280);
}

/// Semantic color tokens exposed as a [ThemeExtension] so they participate
/// in the Material 3 theme system and respond to light/dark switching.
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  final Color success;
  final Color warning;
  final Color info;
  final Color highlightBackground;
  final Color highlightForeground;
  final Color overlay;

  const AppSemanticColors({
    required this.success,
    required this.warning,
    required this.info,
    required this.highlightBackground,
    required this.highlightForeground,
    required this.overlay,
  });

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? warning,
    Color? info,
    Color? highlightBackground,
    Color? highlightForeground,
    Color? overlay,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      highlightBackground: highlightBackground ?? this.highlightBackground,
      highlightForeground: highlightForeground ?? this.highlightForeground,
      overlay: overlay ?? this.overlay,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
      highlightBackground:
          Color.lerp(highlightBackground, other.highlightBackground, t)!,
      highlightForeground:
          Color.lerp(highlightForeground, other.highlightForeground, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
    );
  }

  static const light = AppSemanticColors(
    success: Color(0xFF2E7D32),
    warning: Color(0xFFF57F17),
    info: Color(0xFF1976D2),
    highlightBackground: Color(0xFFFFF59D),
    highlightForeground: Color(0xFF1F1B16),
    overlay: Color(0x1A000000),
  );

  static const dark = AppSemanticColors(
    success: Color(0xFF4CAF50),
    warning: Color(0xFFFFB300),
    info: Color(0xFF90CAF9),
    highlightBackground: Color(0xFF3E2723),
    highlightForeground: Color(0xFFFFF59D),
    overlay: Color(0x33FFFFFF),
  );
}

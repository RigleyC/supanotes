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

  static final ColorScheme darkColorScheme =
      ColorScheme.fromSeed(
        seedColor: primarySeed,
        brightness: Brightness.dark,
      ).copyWith(
        // OLED-friendly true black surfaces so text is always visible.
        surface: const Color(0xFF000000),
        onSurface: const Color(0xFFFFFFFF),
        surfaceContainerLowest: const Color(0xFF0A0A0A),
        surfaceContainerLow: const Color(0xFF111111),
        surfaceContainer: const Color(0xFF1A1A1A),
        surfaceContainerHigh: const Color(0xFF222222),
        surfaceContainerHighest: const Color(0xFF2A2A2A),
        onSurfaceVariant: const Color(0xFFCCCCCC),
      );

  // ---------------------------------------------------------------------------
  // Semantic colors (intentionally identical across light and dark — they
  // // communicate state, not surface ownership).
  // ---------------------------------------------------------------------------

  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);
  static const Color muted = Color(0xFF6B7280);

  // ---------------------------------------------------------------------------
  // Task accent — #7047EB (violet-purple used for all task-related UI).
  // ---------------------------------------------------------------------------

  /// The primary brand colour for tasks.
  /// On dark surfaces this value is used directly; on light surfaces the
  /// [AppSemanticColors.task] token provides a slightly adjusted variant.
  static const Color taskAccent = Color(0xFF7047EB);
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
  final Color task;

  const AppSemanticColors({
    required this.success,
    required this.warning,
    required this.info,
    required this.highlightBackground,
    required this.highlightForeground,
    required this.overlay,
    required this.task,
  });

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? warning,
    Color? info,
    Color? highlightBackground,
    Color? highlightForeground,
    Color? overlay,
    Color? task,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      highlightBackground: highlightBackground ?? this.highlightBackground,
      highlightForeground: highlightForeground ?? this.highlightForeground,
      overlay: overlay ?? this.overlay,
      task: task ?? this.task,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
      highlightBackground: Color.lerp(
        highlightBackground,
        other.highlightBackground,
        t,
      )!,
      highlightForeground: Color.lerp(
        highlightForeground,
        other.highlightForeground,
        t,
      )!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      task: Color.lerp(task, other.task, t)!,
    );
  }

  static const light = AppSemanticColors(
    success: Color(0xFF2E7D32),
    warning: Color(0xFFF57F17),
    info: Color(0xFF1976D2),
    highlightBackground: Color(0xFFFFF59D),
    highlightForeground: Color(0xFF1F1B16),
    overlay: Color(0x1A000000),
    // Slightly darker purple to maintain contrast on light surfaces.
    task: Color(0xFF5B2FD4),
  );

  static const dark = AppSemanticColors(
    success: Color(0xFF4CAF50),
    warning: Color(0xFFFFB300),
    info: Color(0xFF90CAF9),
    highlightBackground: Color(0xFF3E2723),
    highlightForeground: Color(0xFFFFF59D),
    overlay: Color(0x33FFFFFF),
    // Full brand purple on dark backgrounds — pops without feeling harsh.
    task: Color(0xFF7047EB),
  );
}

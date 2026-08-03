import 'package:flutter/material.dart';

/// Color palette for the SupaNotes design system.
///
/// Small color palette based on the Joi colors identified in the research.
///
/// The neutral colors are explicit because they are surface tokens, not brand
/// colors. This keeps the theme predictable in light and dark mode.
class AppColors {
  AppColors._();

  // ---------------------------------------------------------------------------
  // Seed
  // ---------------------------------------------------------------------------

  static const Color joiBlue = Color(0xFF007AFF);
  static const Color primarySeed = joiBlue;

  // ---------------------------------------------------------------------------
  // Light scheme
  // ---------------------------------------------------------------------------

  static final ColorScheme lightColorScheme =
      ColorScheme.fromSeed(
        seedColor: primarySeed,
        brightness: Brightness.light,
      ).copyWith(
        surface: const Color(0xFFFFFFFF),
        onSurface: const Color(0xFF0D0D0D),
        surfaceContainerLowest: const Color(0xFFFFFFFF),
        surfaceContainerLow: const Color(0xFFF5F5F7),
        surfaceContainer: const Color(0xFFF2F2F7),
        surfaceContainerHigh: const Color(0xFFFAFAFA),
        surfaceContainerHighest: const Color(0xFFF2F2F7),
        onSurfaceVariant: const Color(0xFF6E6E73),
        outlineVariant: const Color(0xFFE5E5EA),
      );

  // ---------------------------------------------------------------------------
  // Dark scheme
  // ---------------------------------------------------------------------------

  static final ColorScheme darkColorScheme =
      ColorScheme.fromSeed(
        seedColor: primarySeed,
        brightness: Brightness.dark,
      ).copyWith(
        surface: const Color(0xFF000000),
        onSurface: const Color(0xFFF5F5F7),
        surfaceContainerLowest: const Color(0xFF000000),
        surfaceContainerLow: const Color(0xFF1C1C1E),
        surfaceContainer: const Color(0xFF2C2C2E),
        surfaceContainerHigh: const Color(0xFF2C2C2E),
        surfaceContainerHighest: const Color(0xFF2C2C2E),
        onSurfaceVariant: const Color(0xFFAEAEB2),
        outlineVariant: const Color(0xFF38383A),
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

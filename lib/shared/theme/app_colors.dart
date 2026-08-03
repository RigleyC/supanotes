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
  static const Color joiBlueDark = Color(0xFF0A84FF);
  static const Color joiGreen = Color(0xFF34C759);
  static const Color joiGreenDark = Color(0xFF30D158);
  static const Color joiOrange = Color(0xFFFF9500);
  static const Color joiOrangeDark = Color(0xFFFF9F0A);
  static const Color joiRed = Color(0xFFFF3B30);
  static const Color joiRedDark = Color(0xFFFF453A);
  static const Color joiYellow = Color(0xFFFFCC00);
  static const Color joiYellowDark = Color(0xFFFFD60A);
  static const Color joiIndigo = Color(0xFF5856D6);
  static const Color joiIndigoDark = Color(0xFF5E5CE6);
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
        primary: joiBlue,
        onPrimary: const Color(0xFFFFFFFF),
        primaryContainer: const Color(0xFFD9ECFF),
        onPrimaryContainer: const Color(0xFF001A33),
        secondary: joiIndigo,
        onSecondary: const Color(0xFFFFFFFF),
        tertiary: joiOrange,
        onTertiary: const Color(0xFFFFFFFF),
        error: joiRed,
        onError: const Color(0xFFFFFFFF),
        errorContainer: const Color(0xFFFFDAD6),
        onErrorContainer: const Color(0xFF410002),
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
        primary: joiBlueDark,
        onPrimary: const Color(0xFFFFFFFF),
        primaryContainer: const Color(0xFF004B76),
        onPrimaryContainer: const Color(0xFFCCE5FF),
        secondary: joiIndigoDark,
        onSecondary: const Color(0xFFFFFFFF),
        tertiary: joiOrangeDark,
        onTertiary: const Color(0xFF321300),
        error: joiRedDark,
        onError: const Color(0xFFFFFFFF),
        errorContainer: const Color(0xFF93000A),
        onErrorContainer: const Color(0xFFFFDAD6),
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

  static const Color success = joiGreen;
  static const Color warning = joiOrange;
  static const Color info = joiBlue;
  static const Color muted = Color(0xFF6E6E73);

  // ---------------------------------------------------------------------------
  // Task accent — Joi indigo used for task-related UI.
  // ---------------------------------------------------------------------------

  static const Color taskAccent = joiIndigo;
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
    success: AppColors.joiGreen,
    warning: AppColors.joiOrange,
    info: AppColors.joiBlue,
    highlightBackground: AppColors.joiYellow,
    highlightForeground: Color(0xFF0D0D0D),
    overlay: Color(0x1A000000),
    task: AppColors.joiIndigo,
  );

  static const dark = AppSemanticColors(
    success: AppColors.joiGreenDark,
    warning: AppColors.joiOrangeDark,
    info: AppColors.joiBlueDark,
    highlightBackground: Color(0xFF5C4300),
    highlightForeground: AppColors.joiYellowDark,
    overlay: Color(0x33FFFFFF),
    task: AppColors.joiIndigoDark,
  );
}

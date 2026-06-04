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

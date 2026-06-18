import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supanotes/shared/theme/app_colors.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/theme/app_typography.dart';

/// Border style variant used by [_buildInputBorder].
enum InputBorderType { outline, underline }

OutlineInputBorder _buildInputBorder(InputBorderType type) {
  switch (type) {
    case InputBorderType.outline:
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      );
    case InputBorderType.underline:
      return const OutlineInputBorder();
  }
}

/// Assembles the Material 3 [ThemeData] for the SupaNotes app.
///
/// One [ThemeData] per [Brightness] is built lazily and cached in static
/// fields so repeated reads (e.g. inside [MaterialApp]) are cheap and
/// identity-stable. All numeric values come from the design-system
/// constants in [AppSpacing] / [AppTypography] / [AppColors] — there are
/// no magic numbers here.
class AppTheme {
  AppTheme._();

  /// Cached light theme.
  static final ThemeData lightTheme = buildTheme(Brightness.light);

  /// Cached dark theme.
  static final ThemeData darkTheme = buildTheme(Brightness.dark);

  /// Builds a [ThemeData] for the given [brightness] using the design
  /// system as the single source of truth.
  static ThemeData buildTheme(Brightness brightness) {
    final colorScheme = brightness == Brightness.light
        ? AppColors.lightColorScheme
        : AppColors.darkColorScheme;

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: AppTypography.textTheme.apply(
        bodyColor: colorScheme.onSurface,
        displayColor: colorScheme.onSurface,
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
      fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        /* backgroundColor: colorScheme.surface,
        surfaceTintColor: colorScheme.surfaceTint, */
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLow,
        surfaceTintColor: colorScheme.surfaceTint,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + AppSpacing.xs,
        ),
        border: _buildInputBorder(InputBorderType.outline).copyWith(
          borderSide: BorderSide.none,
        ),
        enabledBorder: _buildInputBorder(InputBorderType.outline).copyWith(
          borderSide: BorderSide.none,
        ),
        focusedBorder: _buildInputBorder(InputBorderType.outline).copyWith(
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: _buildInputBorder(InputBorderType.outline).copyWith(
          borderSide: BorderSide(color: colorScheme.error),
        ),
        labelStyle: AppTypography.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        hintStyle: AppTypography.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: AppTypography.textTheme.labelMedium,
        unselectedLabelStyle: AppTypography.textTheme.labelMedium,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: AppSpacing.elevationMd,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colorScheme.primary,
        selectionHandleColor: colorScheme.primary,
        selectionColor: colorScheme.primary.withValues(alpha: 0.4),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: AppTypography.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
      ),
      extensions: [
        brightness == Brightness.light
            ? AppSemanticColors.light
            : AppSemanticColors.dark,
      ],
    );
  }
}

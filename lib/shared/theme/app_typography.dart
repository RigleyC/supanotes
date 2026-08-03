import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Global typography for SupaNotes.
///
/// Bricolage Grotesk is the app's intentional product font. Components may
/// define local styles when their content needs a different treatment.
class AppTypography {
  AppTypography._();

  static String get fontFamily =>
      GoogleFonts.bricolageGrotesque().fontFamily ?? 'Bricolage Grotesque';

  static TextStyle get codeStyle => const TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: ['Courier', 'monospace'],
  );

  static const double displayLargeSize = 57.0;
  static const double displayMediumSize = 45.0;
  static const double displaySmallSize = 36.0;
  static const double headlineLargeSize = 32.0;
  static const double headlineMediumSize = 28.0;
  static const double headlineSmallSize = 24.0;
  static const double titleLargeSize = 22.0;
  static const double titleMediumSize = 18.0;
  static const double titleSmallSize = 16.0;
  static const double bodyLargeSize = 16.0;
  static const double bodyMediumSize = 14.0;
  static const double bodySmallSize = 12.0;
  static const double labelLargeSize = 14.0;
  static const double labelMediumSize = 12.0;
  static const double labelSmallSize = 11.0;

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;

  static const double displayLetterSpacing = -0.25;
  static const double headlineLetterSpacing = 0.0;
  static const double titleLetterSpacing = 0.0;
  static const double bodyLetterSpacing = 0.5;
  static const double labelLetterSpacing = 0.5;

  static final TextTheme textTheme = _buildTextTheme();

  static TextTheme _buildTextTheme() {
    final base = GoogleFonts.bricolageGrotesqueTextTheme();
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        fontSize: displayLargeSize,
        fontWeight: regular,
        letterSpacing: displayLetterSpacing,
      ),
      displayMedium: base.displayMedium?.copyWith(
        fontSize: displayMediumSize,
        fontWeight: regular,
        letterSpacing: displayLetterSpacing,
      ),
      displaySmall: base.displaySmall?.copyWith(
        fontSize: displaySmallSize,
        fontWeight: regular,
        letterSpacing: displayLetterSpacing,
      ),
      headlineLarge: base.headlineLarge?.copyWith(
        fontSize: headlineLargeSize,
        fontWeight: semibold,
        letterSpacing: headlineLetterSpacing,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: headlineMediumSize,
        fontWeight: semibold,
        letterSpacing: headlineLetterSpacing,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: headlineSmallSize,
        fontWeight: semibold,
        letterSpacing: headlineLetterSpacing,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: titleLargeSize,
        fontWeight: semibold,
        letterSpacing: titleLetterSpacing,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: titleMediumSize,
        fontWeight: semibold,
        letterSpacing: titleLetterSpacing,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: titleSmallSize,
        fontWeight: semibold,
        letterSpacing: titleLetterSpacing,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: bodyLargeSize,
        fontWeight: regular,
        letterSpacing: bodyLetterSpacing,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: bodyMediumSize,
        fontWeight: regular,
        letterSpacing: bodyLetterSpacing,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: bodySmallSize,
        fontWeight: regular,
        letterSpacing: bodyLetterSpacing,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: labelLargeSize,
        fontWeight: medium,
        letterSpacing: labelLetterSpacing,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontSize: labelMediumSize,
        fontWeight: medium,
        letterSpacing: labelLetterSpacing,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: labelSmallSize,
        fontWeight: medium,
        letterSpacing: labelLetterSpacing,
      ),
    );
  }
}

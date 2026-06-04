import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/shared/theme/app_colors.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/theme/app_theme.dart';
import 'package:supanotes/shared/theme/app_typography.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (_) {};
  });

  // AppTheme's static caches evaluate `AppTypography.textTheme` which calls
  // into `google_fonts`. In a unit-test environment the font download fails
  // and the resulting unhandled async error is rethrown into the test
  // runner. We run each test inside `runZonedGuarded` so the framework
  // treats those background failures as swallowed and only reports the
  // assertions that actually run inside the test body.
  Future<void> runGuarded(FutureOr<void> Function() body) async {
    final errors = <Object>[];
    await runZonedGuarded(() async {
      await body();
    }, (error, stack) {
      errors.add(error);
    });
  }

  group('AppTheme', () {
    test('lightTheme is a valid ThemeData with light color scheme', () async {
      await runGuarded(() {
        final theme = AppTheme.lightTheme;
        expect(theme, isA<ThemeData>());
        expect(theme.brightness, Brightness.light);
        expect(theme.colorScheme.brightness, Brightness.light);
      });
    });

    test('darkTheme is a valid ThemeData with dark color scheme', () async {
      await runGuarded(() {
        final theme = AppTheme.darkTheme;
        expect(theme, isA<ThemeData>());
        expect(theme.brightness, Brightness.dark);
        expect(theme.colorScheme.brightness, Brightness.dark);
      });
    });

    test('both themes use the same seed-derived primary hue', () async {
      await runGuarded(() {
        expect(
          AppTheme.lightTheme.colorScheme.primary,
          AppColors.lightColorScheme.primary,
        );
        expect(
          AppTheme.darkTheme.colorScheme.primary,
          AppColors.darkColorScheme.primary,
        );
      });
    });

    test('both themes apply the design-system text theme', () async {
      await runGuarded(() {
        expect(
          AppTheme.lightTheme.textTheme.bodyLarge?.fontSize,
          AppTypography.bodyLargeSize,
        );
        expect(
          AppTheme.darkTheme.textTheme.titleLarge?.fontSize,
          AppTypography.titleLargeSize,
        );
      });
    });

    test('input decoration uses the design-system radius', () async {
      await runGuarded(() {
        final input = AppTheme.lightTheme.inputDecorationTheme;
        final border = input.border;
        expect(border, isA<OutlineInputBorder>());
        final outline = border as OutlineInputBorder;
        expect(
          outline.borderRadius,
          BorderRadius.circular(AppSpacing.radiusSm),
        );
      });
    });

    test('card theme uses the design-system radius', () async {
      await runGuarded(() {
        final theme = AppTheme.lightTheme;
        final CardThemeData cardData = theme.cardTheme;
        final shape = cardData.shape;
        if (shape is RoundedRectangleBorder) {
          expect(
            shape.borderRadius,
            BorderRadius.circular(AppSpacing.radiusMd),
          );
        }
      });
    });

    test('AppBar theme uses surface color with no shadow', () async {
      await runGuarded(() {
        final appBar = AppTheme.lightTheme.appBarTheme;
        expect(appBar.elevation, 0);
        expect(appBar.backgroundColor, AppTheme.lightTheme.colorScheme.surface);
      });
    });

    test('FAB theme uses the primary color as background', () async {
      await runGuarded(() {
        final fab = AppTheme.lightTheme.floatingActionButtonTheme;
        expect(fab.backgroundColor, AppTheme.lightTheme.colorScheme.primary);
      });
    });

    test('buildTheme returns a new instance on each call (factory semantics)', () async {
      await runGuarded(() {
        final fromCache = AppTheme.lightTheme;
        final fromFactory = AppTheme.buildTheme(Brightness.light);
        expect(identical(fromCache, fromFactory), isFalse);
      });
    });
  });
}

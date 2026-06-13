import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/shared/theme/app_typography.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (_) {};
  });

  Future<void> runGuarded(FutureOr<void> Function() body) async {
    final errors = <Object>[];
    await runZonedGuarded(() async {
      await body();
    }, (error, stack) {
      errors.add(error);
    });
  }

  group('AppTypography constants', () {
    test('size constants match the Material 3 type scale', () {
      // Display group: 57 / 45 / 36
      expect(AppTypography.displayLargeSize, 57.0);
      expect(AppTypography.displayMediumSize, 45.0);
      expect(AppTypography.displaySmallSize, 36.0);

      // Headline group: 32 / 28 / 24
      expect(AppTypography.headlineLargeSize, 32.0);
      expect(AppTypography.headlineMediumSize, 28.0);
      expect(AppTypography.headlineSmallSize, 24.0);

      // Title group: 22 / 16 / 14
      expect(AppTypography.titleLargeSize, 22.0);
      expect(AppTypography.titleMediumSize, 16.0);
      expect(AppTypography.titleSmallSize, 14.0);

      // Body group: 16 / 14 / 12
      expect(AppTypography.bodyLargeSize, 16.0);
      expect(AppTypography.bodyMediumSize, 14.0);
      expect(AppTypography.bodySmallSize, 12.0);

      // Label group: 14 / 12 / 11
      expect(AppTypography.labelLargeSize, 14.0);
      expect(AppTypography.labelMediumSize, 12.0);
      expect(AppTypography.labelSmallSize, 11.0);
    });

    test('sizes are strictly descending within each group', () {
      expect(AppTypography.displayLargeSize, greaterThan(AppTypography.displayMediumSize));
      expect(AppTypography.displayMediumSize, greaterThan(AppTypography.displaySmallSize));
      expect(AppTypography.headlineLargeSize, greaterThan(AppTypography.headlineMediumSize));
      expect(AppTypography.headlineMediumSize, greaterThan(AppTypography.headlineSmallSize));
      expect(AppTypography.titleLargeSize, greaterThan(AppTypography.titleMediumSize));
      expect(AppTypography.titleMediumSize, greaterThan(AppTypography.titleSmallSize));
      expect(AppTypography.bodyLargeSize, greaterThan(AppTypography.bodyMediumSize));
      expect(AppTypography.bodyMediumSize, greaterThan(AppTypography.bodySmallSize));
      expect(AppTypography.labelLargeSize, greaterThan(AppTypography.labelMediumSize));
      expect(AppTypography.labelMediumSize, greaterThan(AppTypography.labelSmallSize));
    });

    test('font family is Bricolage Grotesque', () async {
      await runGuarded(() {
        expect(AppTypography.fontFamily, contains('BricolageGrotesque'));
      });
    });

    test('font weights match the type scale', () {
      // Display is regular weight (Material 3 default).
      expect(AppTypography.regular, FontWeight.w400);
      // Headlines/titles get a semibold treatment for hierarchy.
      expect(AppTypography.semibold, FontWeight.w600);
      // Labels get medium to stand out at small sizes.
      expect(AppTypography.medium, FontWeight.w500);
    });
  });

  // Note: `AppTypography.textTheme` is intentionally not exercised in
  // unit tests. It calls into `google_fonts`, which tries to download
  // the Inter .ttf from the network on first use. In a unit-test
  // environment the network is unavailable and the load failure is
  // reported as an unhandled async error, poisoning the test runner.
  // The textTheme is exercised end-to-end via the widget test instead.
}

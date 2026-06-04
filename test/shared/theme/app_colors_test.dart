import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/shared/theme/app_colors.dart';

void main() {
  group('AppColors', () {
    test('primarySeed is a non-null color', () {
      expect(AppColors.primarySeed, isA<Color>());
      expect((AppColors.primarySeed.a * 255.0).round(), 0xFF);
    });

    test('lightColorScheme is a non-null light ColorScheme', () {
      expect(AppColors.lightColorScheme.brightness, Brightness.light);
      expect(AppColors.lightColorScheme.primary, isA<Color>());
    });

    test('darkColorScheme is a non-null dark ColorScheme', () {
      expect(AppColors.darkColorScheme.brightness, Brightness.dark);
      expect(AppColors.darkColorScheme.primary, isA<Color>());
    });

    test('semantic colors are defined and opaque', () {
      expect(AppColors.success, isA<Color>());
      expect(AppColors.warning, isA<Color>());
      expect(AppColors.info, isA<Color>());
      expect(AppColors.muted, isA<Color>());
      for (final c in [AppColors.success, AppColors.warning, AppColors.info, AppColors.muted]) {
        expect(
          (c.a * 255.0).round(),
          0xFF,
          reason: 'semantic color should be fully opaque',
        );
      }
    });

    test('light and dark schemes have distinct primary colors', () {
      expect(
        AppColors.lightColorScheme.primary,
        isNot(equals(AppColors.darkColorScheme.primary)),
        reason: 'light and dark schemes should have distinct primary colors',
      );
    });
  });
}

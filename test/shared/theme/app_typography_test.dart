import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/shared/theme/app_typography.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppTypography', () {
    test('exposes the Material type scale', () {
      expect(AppTypography.bodyLargeSize, 16.0);
      expect(AppTypography.titleLargeSize, 22.0);
      expect(AppTypography.semibold, FontWeight.w600);
    });
  });
}

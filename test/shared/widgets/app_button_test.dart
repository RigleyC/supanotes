import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/shared/widgets/app_button.dart';

void main() {
  group('AppButton Widget Tests', () {
    testWidgets('renders AppButtonVariant.fab with icon and no text required', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: AppButton(
              variant: AppButtonVariant.fab,
              onPressed: () {},
              icon: const Icon(Icons.add),
            ),
          ),
        ),
      );

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('AppButtonVariant.fab uses the light theme action colors', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: AppButton(
              variant: AppButtonVariant.fab,
              onPressed: () {},
              icon: const Icon(Icons.add),
            ),
          ),
        ),
      );

      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      final scheme = ThemeData.light().colorScheme;
      expect(fab.backgroundColor, scheme.primary);
      expect(fab.foregroundColor, scheme.onPrimary);
    });

    testWidgets('AppButtonVariant.fab uses the dark theme action colors', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: AppButton(
              variant: AppButtonVariant.fab,
              onPressed: () {},
              icon: const Icon(Icons.add),
            ),
          ),
        ),
      );

      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      final scheme = ThemeData.dark().colorScheme;
      expect(fab.backgroundColor, scheme.primary);
      expect(fab.foregroundColor, scheme.onPrimary);
    });
  });
}

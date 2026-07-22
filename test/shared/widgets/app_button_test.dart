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

    testWidgets('AppButtonVariant.fab uses black background in light theme', (
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
      expect(fab.backgroundColor, Colors.black);
      expect(fab.foregroundColor, Colors.white);
    });

    testWidgets('AppButtonVariant.fab uses white background in dark theme', (
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
      expect(fab.backgroundColor, Colors.white);
      expect(fab.foregroundColor, Colors.black);
    });
  });
}

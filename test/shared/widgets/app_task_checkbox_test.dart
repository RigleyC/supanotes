import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/shared/widgets/app_task_checkbox.dart';

void main() {
  group('AppTaskCheckbox', () {
    testWidgets('renders outlined circle when value=false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppTaskCheckbox(value: false),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(AppTaskCheckbox),
          matching: find.byType(Container),
        ),
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.color, Colors.transparent);
    });

    testWidgets('renders filled circle when value=true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppTaskCheckbox(
              value: true,
              accentColor: const Color(0xFF000000),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(AppTaskCheckbox),
          matching: find.byType(Container),
        ),
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.color, const Color(0xFF000000));
    });

    testWidgets('renders rounded square when shape=rounded', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppTaskCheckbox(
              value: true,
              shape: AppTaskCheckboxShape.rounded,
              accentColor: const Color(0xFF000000),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(AppTaskCheckbox),
          matching: find.byType(Container),
        ),
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(8));
    });

    testWidgets('is purely visual: tapping it does nothing (no gesture detector)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppTaskCheckbox(value: false),
          ),
        ),
      );

      expect(
        find.ancestor(
          of: find.byType(AppTaskCheckbox),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    });
  });
}

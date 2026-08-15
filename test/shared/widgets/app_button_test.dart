import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/shared/widgets/app_button.dart';

import '../../helpers/haptic_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HapticTestRecorder recorder;

  setUp(() {
    recorder = HapticTestRecorder();
    recorder.install();
  });

  tearDown(() {
    recorder.dispose();
  });

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

    testWidgets('emits light impact when an enabled primary button is tapped', (
      tester,
    ) async {
      var pressedCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(text: 'Salvar', onPressed: () => pressedCount += 1),
          ),
        ),
      );

      await tester.tap(find.text('Salvar'));
      await tester.pump(const Duration(seconds: 1));

      expect(pressedCount, 1);
      expect(recorder.count('HapticFeedbackType.lightImpact'), 1);
    });

    testWidgets('emits no haptic when isLoading is true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(text: 'Salvar', isLoading: true, onPressed: () {}),
          ),
        ),
      );

      await tester.tap(find.byType(AppButton));
      await tester.pump();

      expect(recorder.count('HapticFeedbackType.lightImpact'), 0);
    });

    testWidgets('animates the button while it is pressed', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(text: 'Salvar', onPressed: () {}),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Salvar')),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      final transformFind = find.descendant(
        of: find.byType(AppButton),
        matching: find.byType(Transform),
      );
      final transform = tester.widget<Transform>(transformFind);
      expect(transform.transform.storage[0], lessThan(1));

      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();
    });
  });
}

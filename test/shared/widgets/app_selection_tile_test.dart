import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/shared/widgets/app_selection_tile.dart';

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

  testWidgets('renders label and icon', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSelectionTile(
            label: 'Test Label',
            icon: Icons.ac_unit,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('Test Label'), findsOneWidget);
    expect(find.byIcon(Icons.ac_unit), findsOneWidget);
  });

  testWidgets('calls onTap when pressed', (tester) async {
    bool tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSelectionTile(label: 'Tap Me', onTap: () => tapped = true),
        ),
      ),
    );

    await tester.tap(find.text('Tap Me'));
    expect(tapped, isTrue);
  });

  testWidgets('emits selection click when an unselected tile is tapped', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSelectionTile(label: 'Hoje', onTap: () {}),
        ),
      ),
    );

    await tester.tap(find.text('Hoje'));
    await tester.pump();

    expect(recorder.saw('HapticFeedbackType.selectionClick'), isTrue);
  });

  testWidgets(
    'emits no selection haptic when selected while still calling onTap',
    (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppSelectionTile(
              label: 'Hoje',
              isSelected: true,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Hoje'));
      await tester.pump();

      expect(tapped, isTrue);
      expect(recorder.saw('HapticFeedbackType.selectionClick'), isFalse);
    },
  );
}

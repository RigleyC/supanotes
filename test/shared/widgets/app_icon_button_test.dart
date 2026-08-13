import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/shared/widgets/app_icon_button.dart';

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

  testWidgets('emits light impact when its callback is enabled', (
    tester,
  ) async {
    var pressedCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppIconButton(
            icon: const Icon(Icons.close),
            onPressed: () => pressedCount += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AppIconButton));
    await tester.pump();

    expect(pressedCount, 1);
    expect(recorder.saw('HapticFeedbackType.lightImpact'), isTrue);
  });

  testWidgets('emits no haptic when its callback is disabled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppIconButton(icon: const Icon(Icons.close), onPressed: null),
        ),
      ),
    );

    await tester.tap(find.byType(AppIconButton));
    await tester.pump();

    expect(recorder.saw('HapticFeedbackType.lightImpact'), isFalse);
  });
}

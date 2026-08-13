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
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppIconButton(icon: const Icon(Icons.close), onPressed: () {}),
        ),
      ),
    );

    await tester.tap(find.byType(AppIconButton));
    await tester.pump();

    expect(recorder.saw('HapticFeedbackType.lightImpact'), isTrue);
  });
}

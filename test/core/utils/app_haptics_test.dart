import 'package:flutter_test/flutter_test.dart';

import 'package:supanotes/core/utils/app_haptics.dart';

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

  test('sends light impact for a control tap', () async {
    await AppHaptics.controlTap();

    expect(recorder.count('HapticFeedbackType.lightImpact'), 1);
  });

  test('sends a selection click for a changed selection', () async {
    await AppHaptics.selectionChange();

    expect(recorder.count('HapticFeedbackType.selectionClick'), 1);
  });

  test('sends a medium impact when a task is completed', () async {
    await AppHaptics.taskCompletion();

    expect(recorder.count('HapticFeedbackType.mediumImpact'), 1);
  });

  test('sends a medium impact on long press', () async {
    await AppHaptics.longPress();

    expect(recorder.count('HapticFeedbackType.mediumImpact'), 1);
  });

  test('sends light impact for snackbar', () async {
    await AppHaptics.snackbar();

    expect(recorder.count('HapticFeedbackType.lightImpact'), 1);
  });
}

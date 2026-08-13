import 'package:flutter/services.dart';
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

    expect(recorder.saw('HapticFeedbackType.lightImpact'), isTrue);
  });

  test('sends a selection click for a changed selection', () async {
    await AppHaptics.selectionChange();

    expect(recorder.saw('HapticFeedbackType.selectionClick'), isTrue);
  });
}

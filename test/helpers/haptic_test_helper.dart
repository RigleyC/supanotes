import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class HapticTestRecorder {
  final calls = <MethodCall>[];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
  }

  void dispose() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  }

  int count(String argument) {
    return calls
        .where(
          (call) =>
              call.method == 'HapticFeedback.vibrate' &&
              call.arguments == argument,
        )
        .length;
  }

  bool saw(String argument) => count(argument) > 0;
}

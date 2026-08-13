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

  bool saw(String argument) {
    return calls.any(
      (call) =>
          call.method == 'HapticFeedback.vibrate' && call.arguments == argument,
    );
  }
}

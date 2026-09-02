import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/sync/sync_retry_policy.dart';

void main() {
  test('uses the bounded sync retry schedule', () {
    expect(
      [
        for (var attempt = 1; attempt <= 8; attempt++)
          syncRetryDelayForAttempt(attempt),
      ],
      const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 5),
        Duration(seconds: 10),
        Duration(seconds: 30),
        Duration(seconds: 60),
        Duration(seconds: 60),
        Duration(seconds: 60),
      ],
    );
  });
}

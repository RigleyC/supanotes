import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/sync/remote_sync_pacer.dart';

void main() {
  test('backs off while the feed is quiet and nothing is open', () {
    final pacer = RemoteSyncPacer();
    final delays = <Duration>[];
    for (var i = 0; i < 6; i++) {
      pacer.recordSuccess(changed: false, editing: false);
      delays.add(pacer.nextDelay);
    }
    expect(delays, const [
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 16),
      Duration(seconds: 30),
      Duration(seconds: 30),
      Duration(seconds: 30),
    ]);
  });

  test('keeps the active cadence while changes arrive or a note is open', () {
    final pacer = RemoteSyncPacer();
    pacer.recordSuccess(changed: false, editing: false);
    pacer.recordSuccess(changed: true, editing: false);
    expect(pacer.nextDelay, const Duration(seconds: 2));
    pacer.recordSuccess(changed: false, editing: true);
    expect(pacer.nextDelay, const Duration(seconds: 2));
  });

  test('waits for the delay, or less when woken', () {
    fakeAsync((async) {
      final pacer = RemoteSyncPacer();
      for (var i = 0; i < 4; i++) {
        pacer.recordSuccess(changed: false, editing: false);
      }
      var ran = false;
      pacer.waitForNextRun().then((_) => ran = true);
      async.elapse(const Duration(seconds: 10));
      expect(ran, isFalse);
      pacer.wake();
      async.flushMicrotasks();
      expect(ran, isTrue);
      expect(pacer.nextDelay, const Duration(seconds: 2));
    });
  });

  test('does not run in the background until the app resumes', () {
    fakeAsync((async) {
      final pacer = RemoteSyncPacer()..setForeground(false);
      var ran = false;
      pacer.waitForNextRun().then((_) => ran = true);
      async.elapse(const Duration(minutes: 10));
      expect(ran, isFalse);
      pacer.setForeground(true);
      async.flushMicrotasks();
      expect(ran, isTrue);
    });
  });
}

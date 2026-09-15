import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/sync/task_outbox_worker.dart';

void main() {
  test('drains task ids in deterministic loader order', () async {
    final calls = <String>[];
    final worker = TaskOutboxWorker(
      loadPendingTaskIds: () async => ['task-a', 'task-b'],
      syncTask: (taskId) async => calls.add(taskId),
    );
    addTearDown(worker.dispose);

    await worker.drain();

    expect(calls, ['task-a', 'task-b']);
  });

  test('transient failures honor backoff and wake resets it', () async {
    var now = DateTime.utc(2026, 9, 15, 12);
    var attempts = 0;
    final worker = TaskOutboxWorker(
      loadPendingTaskIds: () async => ['task-a'],
      syncTask: (_) async {
        attempts++;
        if (attempts == 1) throw Exception('offline');
      },
      now: () => now,
      backoffForAttempt: (_) => const Duration(seconds: 1),
    );
    addTearDown(worker.dispose);

    await worker.drain();
    await worker.drain();
    expect(attempts, 1);

    now = now.add(const Duration(seconds: 1));
    await worker.drain();
    expect(attempts, 2);

    // A meaningful lifecycle wake retries immediately even before the normal
    // backoff deadline is reached.
    now = now.subtract(const Duration(seconds: 1));
    var completed = Completer<void>();
    final wakeWorker = TaskOutboxWorker(
      loadPendingTaskIds: () async => ['task-b'],
      syncTask: (_) async {
        completed.complete();
        throw Exception('offline');
      },
      now: () => now,
      backoffForAttempt: (_) => const Duration(minutes: 1),
    );
    addTearDown(wakeWorker.dispose);
    await wakeWorker.drain();
    completed = Completer<void>();
    wakeWorker.wake();
    await completed.future;
  });

  test('protocol errors are suppressed until an explicit wake', () async {
    var attempts = 0;
    final worker = TaskOutboxWorker(
      loadPendingTaskIds: () async => ['task-a'],
      syncTask: (_) async {
        attempts++;
        throw const FormatException('bad protocol');
      },
    );
    addTearDown(worker.dispose);

    await worker.drain();
    await worker.drain();
    expect(attempts, 1);
    worker.wake();
    await Future<void>.delayed(Duration.zero);
    expect(attempts, 2);
  });

  test('concurrent drains never run the same task concurrently', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    var active = 0;
    var maximum = 0;
    final worker = TaskOutboxWorker(
      loadPendingTaskIds: () async => ['task-a'],
      syncTask: (_) async {
        active++;
        maximum = active > maximum ? active : maximum;
        started.complete();
        await release.future;
        active--;
      },
    );
    addTearDown(worker.dispose);

    final first = worker.drain();
    await started.future;
    final second = worker.drain();
    release.complete();
    await Future.wait([first, second]);

    expect(maximum, 1);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/sync/task_outbox_worker.dart';
import 'package:supanotes/features/tasks/data/task_repository.dart';
import 'package:supanotes/features/tasks/domain/task.dart';

class _CountingTaskOutboxWorker extends TaskOutboxWorker {
  _CountingTaskOutboxWorker()
    : super(
        loadPendingTaskIds: () async => const [],
        syncTask: (_) async {},
      );

  int wakeCount = 0;

  @override
  void wake({bool resetBackoff = true}) {
    wakeCount++;
  }
}

Task _task() => Task(
  id: 'task-1',
  ownerUserId: 'user-a',
  title: 'Review',
  createdAt: DateTime.utc(2026, 9, 15),
  updatedAt: DateTime.utc(2026, 9, 15),
);

void main() {
  testWidgets('mutation after auto-dispose still wakes the outbox', (
    tester,
  ) async {
    final database = AppDatabase.test();
    final worker = _CountingTaskOutboxWorker();
    late TaskRepository repository;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          currentUserIdProvider.overrideWithValue('user-a'),
          taskOutboxWorkerProvider.overrideWithValue(worker),
        ],
        // Mirrors the editor: it only `ref.read`s the repository without
        // listening, so the auto-dispose provider is gone once frames settle
        // and the async mutation completes afterwards.
        child: Consumer(
          builder: (context, ref, _) {
            repository = ref.read(taskRepositoryProvider);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final created = await repository.create(_task());

    expect(created.title, 'Review');
    expect(worker.wakeCount, 1);
    expect(
      await database.tasksDao.getPendingOperations('user-a', 'task-1'),
      hasLength(1),
    );
  });
}

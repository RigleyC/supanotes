import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/tasks/data/task_api.dart';
import 'package:supanotes/features/tasks/data/task_repository.dart';
import 'package:supanotes/features/tasks/data/task_sync_service.dart';
import 'package:supanotes/features/tasks/domain/task.dart';
import 'package:supanotes/features/tasks/domain/task_operation.dart';

class _MockTaskApi extends Mock implements TaskApi {}

class _FakeTaskOperation extends Fake implements TaskOperation {}

Task _task({String title = 'Initial'}) => Task(
  id: 'task-1',
  ownerUserId: 'user-a',
  title: title,
  createdAt: DateTime.utc(2026, 9, 15),
  updatedAt: DateTime.utc(2026, 9, 15),
);

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeTaskOperation());
  });

  test(
    'confirms only response operation and rebases later operations',
    () async {
      final db = AppDatabase.test();
      addTearDown(db.close);
      final repository = TaskRepository(db.tasksDao, 'user-a');
      final api = _MockTaskApi();
      await repository.create(_task());
      await repository.update(_task(title: 'Updated'));
      await repository.completeOccurrence(
        taskId: 'task-1',
        scheduledAt: '2026-09-15T00:00:00',
      );
      final before = await db.tasksDao.getPendingOperations('user-a', 'task-1');
      final middle = before[1];
      await db.tasksDao.updatePendingStatus(middle.operationId, 'in_flight');
      when(() => api.mutate(any())).thenAnswer((invocation) async {
        final operation =
            invocation.positionalArguments.single as TaskOperation;
        expect(operation.operationId, middle.operationId);
        return TaskMutationResponse(
          operationId: middle.operationId,
          revision: 2,
          task: _task(title: 'Updated').copyWith(revision: 2),
        );
      });

      await TaskSyncService(
        api: api,
        repository: repository,
      ).syncTask('task-1');

      final after = await db.tasksDao.getPendingOperations('user-a', 'task-1');
      expect(after.map((operation) => operation.operationId), [
        before[0].operationId,
        before[2].operationId,
      ]);
      expect(after.map((operation) => operation.status), [
        'pending',
        'pending',
      ]);
      expect((await repository.get('task-1'))!.title, 'Updated');
      expect((await repository.get('task-1'))!.revision, 2);
    },
  );

  test('marks schedule and deleted protocol responses blocked', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final repository = TaskRepository(db.tasksDao, 'user-a');
    final api = _MockTaskApi();
    await repository.create(_task());
    final operation = (await db.tasksDao.getPendingOperations(
      'user-a',
      'task-1',
    )).single;
    when(() => api.mutate(any())).thenThrow(
      const ConflictException(message: 'SCHEDULE_CHANGED'),
    );

    await TaskSyncService(api: api, repository: repository).syncTask('task-1');
    expect(
      (await db.tasksDao.getPendingOperations(
        'user-a',
        'task-1',
      )).single.status,
      'blocked',
    );

    await db.tasksDao.updatePendingStatus(operation.operationId, 'pending');
    when(() => api.mutate(any())).thenThrow(
      const ApiException(message: 'TASK_DELETED', statusCode: 410),
    );
    await TaskSyncService(api: api, repository: repository).syncTask('task-1');
    expect(
      (await db.tasksDao.getPendingOperations(
        'user-a',
        'task-1',
      )).single.status,
      'blocked',
    );
  });

  test(
    'keeps transient failure pending with attempt metadata and serializes calls',
    () async {
      final db = AppDatabase.test();
      addTearDown(db.close);
      final repository = TaskRepository(db.tasksDao, 'user-a');
      final api = _MockTaskApi();
      await repository.create(_task());
      final release = Completer<void>();
      var active = 0;
      var maximum = 0;
      when(() => api.mutate(any())).thenAnswer((_) async {
        active++;
        maximum = active > maximum ? active : maximum;
        await release.future;
        active--;
        throw const NetworkException(message: 'offline');
      });
      final service = TaskSyncService(api: api, repository: repository);
      final first = service.syncTask('task-1');
      final second = service.syncTask('task-1');
      await Future<void>.delayed(Duration.zero);
      release.complete();
      await Future.wait([
        first.catchError((_) {}),
        second.catchError((_) {}),
      ]);

      expect(maximum, 1);
      final operation = (await db.tasksDao.getPendingOperations(
        'user-a',
        'task-1',
      )).single;
      expect(operation.status, 'pending');
      expect(operation.attemptCount, 2);
      expect(operation.lastAttemptAt, isNotNull);
    },
  );
}

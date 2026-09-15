import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/tasks/data/task_repository.dart';
import 'package:supanotes/features/tasks/domain/task.dart';

Task _task({String id = 'task-1', String owner = 'user-a'}) => Task(
  id: id,
  ownerUserId: owner,
  title: 'Review',
  createdAt: DateTime.utc(2026, 9, 15),
  updatedAt: DateTime.utc(2026, 9, 15),
);

void main() {
  test(
    'create writes the task and exactly one outbox operation atomically',
    () async {
      final db = AppDatabase.test();
      addTearDown(db.close);
      final repository = TaskRepository(db.tasksDao, 'user-a');

      final created = await repository.create(_task());

      expect(
        (await db.tasksDao.getTask('user-a', created.id))!.title,
        'Review',
      );
      final operations = await db.tasksDao.getPendingOperations(
        'user-a',
        created.id,
      );
      expect(operations, hasLength(1));
      expect(operations.single.taskId, created.id);
      expect(operations.single.kind, 'create');
      expect(operations.single.payloadHash, isNotEmpty);
    },
  );

  test(
    'delete keeps an owner-scoped tombstone and queues the mutation',
    () async {
      final db = AppDatabase.test();
      addTearDown(db.close);
      final repository = TaskRepository(db.tasksDao, 'user-a');
      await repository.create(_task());

      final deleted = await repository.delete('task-1');

      expect(deleted.deletedAt, isNotNull);
      expect(await db.tasksDao.watchTasks('user-a').first, isEmpty);
      expect(
        (await db.tasksDao.getTask('user-a', 'task-1'))!.deletedAt,
        isNotNull,
      );
      final operations = await db.tasksDao.getPendingOperations(
        'user-a',
        'task-1',
      );
      expect(operations.map((operation) => operation.kind), [
        'create',
        'delete',
      ]);
    },
  );

  test(
    'recurring completion is represented by the canonical occurrence key',
    () async {
      final db = AppDatabase.test();
      addTearDown(db.close);
      final repository = TaskRepository(db.tasksDao, 'user-a');
      await repository.create(
        _task().copyWith(
          dueDate: DateTime.utc(2026, 9, 15, 9),
          hasTime: true,
          recurrenceRule: 'daily',
        ),
      );

      final completed = await repository.completeOccurrence(
        taskId: 'task-1',
        scheduledAt: '2026-09-15T09:00:00',
      );

      expect(completed.completions, contains('2026-09-15T09:00:00.000'));
      expect(
        (await db.tasksDao.getPendingOperations('user-a', 'task-1')).last.kind,
        'complete_occurrence',
      );
    },
  );

  test('update derives schedule generation from current task', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final repository = TaskRepository(db.tasksDao, 'user-a');
    final scheduled = _task().copyWith(
      dueDate: DateTime.utc(2026, 9, 15, 9),
      hasTime: true,
      recurrenceRule: 'daily',
      reminder: 'at_time',
      completions: {
        '2026-09-15T09:00:00': '2026-09-15T10:00:00Z',
      },
      scheduleGeneration: 3,
    );
    await repository.create(scheduled);

    final reminderOnly = await repository.update(
      scheduled.copyWith(
        reminder: '5m_before',
        scheduleGeneration: 99,
        completions: {
          '2026-09-16T09:00:00': '2026-09-16T10:00:00Z',
        },
      ),
    );

    expect(reminderOnly.scheduleGeneration, 3);
    expect(reminderOnly.completions, scheduled.completions);
    expect(reminderOnly.reminder, '5m_before');

    final cleared = await repository.update(
      reminderOnly.copyWith(
        dueDate: null,
        hasTime: false,
        recurrenceRule: null,
        scheduleGeneration: 0,
        completions: {
          '2026-09-15T09:00:00': '2026-09-15T10:00:00Z',
        },
      ),
    );

    expect(cleared.scheduleGeneration, 4);
    expect(cleared.dueDate, isNull);
    expect(cleared.recurrenceRule, isNull);
    expect(cleared.completions, isEmpty);
  });

  test(
    'remote rebase leaves schedule-conflicting operations blocked',
    () async {
      final db = AppDatabase.test();
      addTearDown(db.close);
      final repository = TaskRepository(db.tasksDao, 'user-a');
      final base = _task().copyWith(
        dueDate: DateTime.utc(2026, 9, 15, 9),
        hasTime: true,
        recurrenceRule: 'daily',
      );
      await repository.applyRemoteTask(base);
      final local = await repository.update(
        base.copyWith(dueDate: DateTime.utc(2026, 9, 16, 9)),
      );

      final remote = base.copyWith(
        dueDate: DateTime.utc(2026, 9, 17, 9),
        revision: 1,
        scheduleGeneration: 1,
        updatedAt: DateTime.utc(2026, 9, 15, 12),
      );
      await repository.applyRemoteTask(remote);

      final stored = await repository.get('task-1');
      expect(stored!.dueDate, remote.dueDate);
      expect(stored.scheduleGeneration, remote.scheduleGeneration);
      expect(stored.title, remote.title);
      expect(local.scheduleGeneration, 1);
      final operations = await db.tasksDao.getPendingOperations(
        'user-a',
        'task-1',
      );
      expect(operations, hasLength(1));
      expect(operations.single.status, 'blocked');
      expect(repository.lastRebaseDiagnostic?.hasConflicts, isTrue);
      expect(
        repository.lastRebaseDiagnostic!.conflicts.single.operationId,
        operations.single.operationId,
      );
    },
  );

  test(
    'remote rebase blocks chained schedule edits after the first conflict',
    () async {
      final db = AppDatabase.test();
      addTearDown(db.close);
      final repository = TaskRepository(db.tasksDao, 'user-a');
      final base = _task().copyWith(
        dueDate: DateTime.utc(2026, 9, 15, 9),
        hasTime: true,
        recurrenceRule: 'daily',
      );
      await repository.applyRemoteTask(base);
      await repository.update(
        base.copyWith(dueDate: DateTime.utc(2026, 9, 16, 9)),
      );
      await repository.update(
        base.copyWith(dueDate: DateTime.utc(2026, 9, 17, 9)),
      );

      final remote = base.copyWith(
        dueDate: DateTime.utc(2026, 9, 18, 9),
        revision: 1,
        scheduleGeneration: 1,
        updatedAt: DateTime.utc(2026, 9, 15, 12),
      );
      await repository.applyRemoteTask(remote);

      final stored = await repository.get('task-1');
      expect(stored!.dueDate, remote.dueDate);
      expect(stored.scheduleGeneration, remote.scheduleGeneration);
      final operations = await db.tasksDao.getPendingOperations(
        'user-a',
        'task-1',
      );
      expect(operations.map((operation) => operation.status), [
        'blocked',
        'blocked',
      ]);
      expect(repository.lastRebaseDiagnostic!.conflicts, hasLength(2));
      expect(
        repository.lastRebaseDiagnostic!.conflicts.map(
          (conflict) => conflict.operationId,
        ),
        operations.map((operation) => operation.operationId),
      );
    },
  );

  test(
    'remote rebase blocks completion after a conflicting schedule edit',
    () async {
      final db = AppDatabase.test();
      addTearDown(db.close);
      final repository = TaskRepository(db.tasksDao, 'user-a');
      final base = _task().copyWith(
        dueDate: DateTime.utc(2026, 9, 15, 9),
        hasTime: true,
        recurrenceRule: 'daily',
      );
      await repository.applyRemoteTask(base);
      await repository.update(
        base.copyWith(dueDate: DateTime.utc(2026, 9, 16, 9)),
      );
      await repository.completeOccurrence(
        taskId: 'task-1',
        scheduledAt: '2026-09-16T09:00:00',
        completedAt: DateTime.utc(2026, 9, 15, 10),
      );

      final remote = base.copyWith(
        dueDate: DateTime.utc(2026, 9, 17, 9),
        revision: 1,
        scheduleGeneration: 1,
        updatedAt: DateTime.utc(2026, 9, 15, 12),
      );
      await repository.applyRemoteTask(remote);

      final stored = await repository.get('task-1');
      expect(stored!.dueDate, remote.dueDate);
      expect(stored.completions, isEmpty);
      final operations = await db.tasksDao.getPendingOperations(
        'user-a',
        'task-1',
      );
      expect(operations.map((operation) => operation.status), [
        'blocked',
        'blocked',
      ]);
      expect(repository.lastRebaseDiagnostic!.conflicts, hasLength(2));
      expect(
        repository.lastRebaseDiagnostic!.conflicts.last.operationKind,
        'complete_occurrence',
      );
    },
  );

  test(
    'remote rebase reapplies schedule operation from matching generation',
    () async {
      final db = AppDatabase.test();
      addTearDown(db.close);
      final repository = TaskRepository(db.tasksDao, 'user-a');
      final base = _task().copyWith(
        dueDate: DateTime.utc(2026, 9, 15, 9),
        hasTime: true,
        recurrenceRule: 'daily',
      );
      await repository.applyRemoteTask(base);
      final local = await repository.update(
        base.copyWith(dueDate: DateTime.utc(2026, 9, 16, 9)),
      );

      await repository.applyRemoteTask(
        base.copyWith(revision: 1, updatedAt: DateTime.utc(2026, 9, 15, 12)),
      );

      final stored = await repository.get('task-1');
      expect(stored!.dueDate, local.dueDate);
      expect(stored.scheduleGeneration, local.scheduleGeneration);
      expect(repository.lastRebaseDiagnostic, isNull);
      expect(
        (await db.tasksDao.getPendingOperations(
          'user-a',
          'task-1',
        )).single.status,
        'pending',
      );
    },
  );

  test('remote snapshots are rebased over pending local operations', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final repository = TaskRepository(db.tasksDao, 'user-a');
    await repository.create(_task());
    final local = await repository.update(_task().copyWith(title: 'Local'));

    await repository.applyRemoteTask(
      _task().copyWith(
        title: 'Remote',
        revision: 1,
        updatedAt: DateTime.utc(2026, 9, 15, 12),
      ),
    );

    final stored = await db.tasksDao.getTask('user-a', 'task-1');
    expect(stored!.title, local.title);
    expect(stored.revision, 1);
    expect(
      await db.tasksDao.getPendingOperations('user-a', 'task-1'),
      hasLength(2),
    );
  });
}

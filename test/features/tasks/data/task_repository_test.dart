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
  test('create writes the task and exactly one outbox operation atomically', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final repository = TaskRepository(db.tasksDao, 'user-a');

    final created = await repository.create(_task());

    expect((await db.tasksDao.getTask('user-a', created.id))!.title, 'Review');
    final operations = await db.tasksDao.getPendingOperations(
      'user-a',
      created.id,
    );
    expect(operations, hasLength(1));
    expect(operations.single.taskId, created.id);
    expect(operations.single.kind, 'create');
    expect(operations.single.payloadHash, isNotEmpty);
  });

  test('delete keeps an owner-scoped tombstone and queues the mutation', () async {
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
  });

  test('recurring completion is represented by the canonical occurrence key', () async {
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
  });
}

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/database/database.dart';

void main() {
  test('watchTasks filters by owner and hides tombstones', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final now = DateTime.utc(2026, 9, 15);

    for (final task in [
      TasksCompanion.insert(
        id: 'visible',
        ownerUserId: 'user-a',
        title: 'Visible',
        createdAt: now,
        updatedAt: now,
      ),
      TasksCompanion.insert(
        id: 'other-owner',
        ownerUserId: 'user-b',
        title: 'Other',
        createdAt: now,
        updatedAt: now,
      ),
      TasksCompanion.insert(
        id: 'tombstone',
        ownerUserId: 'user-a',
        title: 'Deleted',
        createdAt: now,
        updatedAt: now,
        deletedAt: Value(now),
      ),
    ]) {
      await db.into(db.tasks).insert(task);
    }

    final tasks = await db.tasksDao.watchTasks('user-a').first;
    expect(tasks.map((task) => task.id), ['visible']);
    expect(await db.tasksDao.watchTask('user-a', 'tombstone').first, isNotNull);
    expect(await db.tasksDao.watchTask('user-a', 'other-owner').first, isNull);
  });

  test('enqueueMutation stores one ordered operation', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final now = DateTime.utc(2026, 9, 15);

    await db.tasksDao.enqueueMutation(
      PendingTaskOperationsCompanion.insert(
        operationId: 'operation-1',
        taskId: 'task-1',
        ownerUserId: 'user-a',
        observedRevision: 0,
        scheduleGeneration: 0,
        ordinal: 0,
        kind: 'create',
        payloadJson: '{"title":"Task"}',
        payloadHash: 'hash-1',
        createdAt: now,
      ),
    );

    final operations = await db.tasksDao
        .watchPendingOperations('user-a', 'task-1')
        .first;
    expect(operations, hasLength(1));
    expect(operations.single.operationId, 'operation-1');
    expect(operations.single.payloadHash, 'hash-1');
  });

  test(
    'schema 32 quarantines non-empty legacy task tables without dropping notes outbox',
    () async {
      final db = AppDatabase.test();
      addTearDown(db.close);

      await db.customStatement('DROP TABLE tasks');
      await db.customStatement(
        'CREATE TABLE tasks (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL)',
      );
      await db.customStatement(
        "INSERT INTO tasks(id, title) VALUES ('legacy', 'Old')",
      );
      await db.customStatement(
        'CREATE TABLE task_completions (task_id TEXT NOT NULL, completed_at INTEGER)',
      );
      await db.customStatement(
        "INSERT INTO task_completions(task_id, completed_at) VALUES ('legacy', 1)",
      );
      await db.customStatement(
        'CREATE TABLE local_task_completions (task_id TEXT NOT NULL, completed_at INTEGER)',
      );

      await db.migration.onUpgrade(Migrator(db), 32, 33);

      expect(db.taskStorageDiagnostic.isBlocked, isTrue);
      expect(db.taskStorageDiagnostic.quarantinedRows.values, contains(1));
      expect(
        (await db
                .customSelect(
                  'SELECT COUNT(*) AS count FROM tasks_legacy_quarantine_v32',
                )
                .getSingle())
            .data['count'],
        1,
      );
      expect(await db.select(db.tasks).get(), isEmpty);
    },
  );

  test('task diagnostic includes suffixed quarantine tables', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);

    await db.customStatement(
      'CREATE TABLE tasks_legacy_quarantine_v32_1 (id TEXT NOT NULL)',
    );
    await db.customStatement(
      "INSERT INTO tasks_legacy_quarantine_v32_1(id) VALUES ('legacy')",
    );

    final diagnostic = await db.readTaskStorageDiagnostic();

    expect(diagnostic.isBlocked, isTrue);
    expect(diagnostic.quarantinedRows['tasks_legacy_quarantine_v32_1'], 1);
  });
}

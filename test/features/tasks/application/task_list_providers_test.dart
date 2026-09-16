import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/tasks/application/task_list_providers.dart';
import 'package:supanotes/features/tasks/domain/task.dart';

Task _task(
  String id,
  DateTime createdAt, {
  DateTime? dueDate,
  bool hasTime = false,
  bool isCompleted = false,
  DateTime? lastCompletedAt,
  String? recurrenceRule,
  Map<String, Object?> completions = const {},
}) => Task(
  id: id,
  ownerUserId: 'user-1',
  title: id,
  dueDate: dueDate,
  hasTime: hasTime,
  recurrenceRule: recurrenceRule,
  isCompleted: isCompleted,
  lastCompletedAt: lastCompletedAt,
  completions: completions,
  createdAt: createdAt,
  updatedAt: createdAt,
);

VisibleNoteDocument _noteDocument({
  required String noteId,
  required String blockId,
  required String title,
  required String dueDate,
  bool hideCompleted = true,
  bool isCompleted = false,
  String? lastCompletedAt,
}) => VisibleNoteDocument(
  noteId: noteId,
  noteTitle: 'Origem',
  hideCompleted: hideCompleted,
  documentJson: jsonEncode({
    'schemaVersion': 1,
    'blocks': [
      {
        'id': blockId,
        'type': 'task',
        'delta': [
          {'insert': title},
        ],
        'metadata': {
          'dueDate': dueDate,
          'hasTime': false,
          'isCompleted': isCompleted,
          if (lastCompletedAt != null) 'lastCompletedAt': lastCompletedAt,
        },
      },
    ],
  }),
);

void main() {
  final now = DateTime(2026, 9, 15, 10);

  test('merges sources in overdue, today, future and undated order', () {
    final result = buildTaskList(
      now: now,
      includeNoteTasks: true,
      standalone: [
        _task('future', DateTime(2026, 9, 1), dueDate: DateTime(2026, 9, 16)),
        _task('undated', DateTime(2026, 9, 2)),
        _task('today', DateTime(2026, 9, 3), dueDate: DateTime(2026, 9, 15)),
        _task('overdue', DateTime(2026, 9, 4), dueDate: DateTime(2026, 9, 14)),
      ],
      notes: [
        _noteDocument(
          noteId: 'note-1',
          blockId: 'block-1',
          title: 'Nota futura',
          dueDate: '2026-09-17T00:00:00.000',
        ),
      ],
    );

    expect(result.map((item) => item.task?.id ?? item.note!.title), [
      'overdue',
      'today',
      'future',
      'Nota futura',
      'undated',
    ]);
    expect(result.last.uiKey, 'standalone:undated');
  });

  test('uses a composite source key when task ids collide', () {
    final result = buildTaskList(
      now: now,
      includeNoteTasks: true,
      standalone: [
        _task('same-id', DateTime(2026, 9, 1)),
      ],
      notes: [
        _noteDocument(
          noteId: 'note-1',
          blockId: 'same-id',
          title: 'Nota',
          dueDate: '2026-09-17T00:00:00.000',
        ),
      ],
    );

    expect(result.map((item) => item.uiKey), [
      'note:note-1:same-id',
      'standalone:same-id',
    ]);
  });

  test('projects standalone and note completion history newest first', () {
    final result = buildCompletedTaskHistory(
      includeNoteTasks: true,
      standalone: [
        _task(
          'single',
          DateTime(2026, 9, 1),
          isCompleted: true,
          lastCompletedAt: DateTime.utc(2026, 9, 15, 12),
        ),
        _task(
          'recurring',
          DateTime(2026, 9, 1),
          recurrenceRule: 'daily',
          completions: {
            '2026-09-14T09:00:00.000': '2026-09-14T12:00:00.000Z',
            '2026-09-15T09:00:00.000': '2026-09-15T13:00:00.000Z',
          },
        ),
      ],
      notes: [
        _noteDocument(
          noteId: 'note-1',
          blockId: 'note-task',
          title: 'Nota concluída',
          dueDate: '2026-09-14T00:00:00.000',
          isCompleted: true,
          lastCompletedAt: '2026-09-15T11:00:00.000Z',
        ),
      ],
    );

    expect(result, hasLength(4));
    expect(result.first.completedAt, DateTime.utc(2026, 9, 15, 13));
    expect(result[1].completedAt, DateTime.utc(2026, 9, 15, 12));
    expect(result[2].task.isNote, isTrue);
  });

  test('taskListProvider observes the owner-scoped Drift stream', () async {
    final database = AppDatabase.test();
    final now = DateTime(2026, 9, 15, 10);
    await database.tasksDao.insertOrUpdateTask(
      TasksCompanion.insert(
        id: 'task-1',
        ownerUserId: 'user-1',
        title: 'Abrir tarefa',
        dueDate: Value(DateTime(2026, 9, 15)),
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      ),
    );
    await database.tasksDao.insertOrUpdateTask(
      TasksCompanion.insert(
        id: 'task-done',
        ownerUserId: 'user-1',
        title: 'Concluída',
        isCompleted: const Value(true),
        lastCompletedAt: Value(DateTime.utc(2026, 9, 14, 12)),
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        currentUserIdProvider.overrideWithValue('user-1'),
        taskListClockProvider.overrideWithValue(TaskListClock(() => now)),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    final subscription = container.listen(
      taskListProvider(includeNoteTasks: false),
      (_, _) {},
    );
    addTearDown(subscription.close);
    final items = await container.read(
      taskListProvider(includeNoteTasks: false).future,
    );

    expect(items, hasLength(1));
    expect(items.single.task!.id, 'task-1');
  });
}

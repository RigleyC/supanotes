import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/database/note_lifecycle_policy.dart';
import 'package:supanotes/features/tasks/application/task_list_providers.dart';
import 'package:supanotes/features/tasks/domain/task.dart';
import 'package:supanotes/features/tasks/domain/task_list_item.dart';

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
  String? dueDate,
  bool hideCompleted = true,
  bool isCompleted = false,
  String? lastCompletedAt,
  DateTime? createdAt,
}) => VisibleNoteDocument(
  noteId: noteId,
  noteTitle: 'Origem',
  hideCompleted: hideCompleted,
  createdAt: createdAt,
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
          if (dueDate != null) 'dueDate': dueDate,
          'hasTime': false,
          'isCompleted': isCompleted,
          if (lastCompletedAt != null) 'lastCompletedAt': lastCompletedAt,
        },
      },
    ],
  }),
);

class _ManualTimer implements Timer {
  _ManualTimer(this.callback, {required this.delay});

  final void Function() callback;
  final Duration delay;
  bool _isActive = true;
  int _tick = 0;

  void fire() {
    if (!_isActive) return;
    _isActive = false;
    _tick = 1;
    callback();
  }

  @override
  void cancel() => _isActive = false;

  @override
  bool get isActive => _isActive;

  @override
  int get tick => _tick;
}

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

  test(
    'sorts undated note and standalone tasks by createdAt across sources',
    () {
      final result = buildTaskList(
        now: now,
        includeNoteTasks: true,
        standalone: [
          _task('newer', DateTime(2026, 9, 15, 12)),
          _task('older', DateTime(2026, 9, 15, 8)),
        ],
        notes: [
          _noteDocument(
            noteId: 'note-1',
            blockId: 'note-task',
            title: 'Nota do meio',
            createdAt: DateTime(2026, 9, 15, 10),
          ),
        ],
      );

      expect(result.map((item) => item.task?.id ?? item.note!.title), [
        'older',
        'Nota do meio',
        'newer',
      ]);
      expect(result.map((item) => item.createdAt), [
        DateTime(2026, 9, 15, 8),
        DateTime(2026, 9, 15, 10),
        DateTime(2026, 9, 15, 12),
      ]);
    },
  );

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

  test(
    'scopes cached shared note tasks to the authenticated account',
    () async {
      final database = AppDatabase.test();
      final createdAt = DateTime.utc(2026, 9, 15);
      final document = jsonEncode({
        'schemaVersion': 1,
        'blocks': [
          {
            'id': 'task-block',
            'type': 'task',
            'delta': [
              {'insert': 'Tarefa compartilhada'},
            ],
            'metadata': {'isCompleted': false},
          },
        ],
      });

      Future<void> insertNote({
        required String id,
        required String userId,
        String? permission,
      }) async {
        await database.notesDao.createNote(
          NotesCompanion.insert(
            id: id,
            userId: userId,
            content: 'Nota $id',
            createdAt: createdAt,
            updatedAt: createdAt,
            hasRemoteCopy: const Value(true),
            lifecycleState: const Value(materializedLifecycleState),
            permission: Value(permission),
          ),
        );
        await database.noteOperationsDao.upsertNoteDocument(
          LocalNoteDocumentsCompanion.insert(
            noteId: id,
            revision: 1,
            documentJson: document,
            updatedAt: createdAt,
            materializedDocumentJson: Value(document),
            materializedUpdatedAt: Value(createdAt),
          ),
        );
      }

      // These rows were cached while user-a was authenticated. Their stale
      // view/edit metadata must not grant user-b access after expiry.
      await insertNote(
        id: 'cached-view-from-a',
        userId: 'user-a',
        permission: 'view',
      );
      await insertNote(
        id: 'cached-edit-from-a',
        userId: 'user-a',
        permission: 'edit',
      );

      // A shared note with a current-account membership remains visible even
      // when its cached row retains the note owner's local user id.
      await insertNote(
        id: 'authorized-for-b',
        userId: 'user-a',
        permission: 'view',
      );
      await database.userNotePreferencesDao.applyRemotePreference(
        userId: 'user-b',
        noteId: 'authorized-for-b',
        favorite: false,
        archived: false,
        hideCompleted: false,
        collapseImages: false,
        remoteUpdatedAt: createdAt,
      );
      await insertNote(id: 'own-note-for-b', userId: 'user-b');

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          currentUserIdProvider.overrideWithValue('user-b'),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      final visibleNotesSubscription = container.listen(
        taskNotesVisibilityProvider,
        (_, _) {},
      );
      final taskListSubscription = container.listen(
        taskListProvider(includeNoteTasks: true),
        (_, _) {},
      );
      addTearDown(() {
        visibleNotesSubscription.close();
        taskListSubscription.close();
      });

      final visibleNotes = await container.read(
        taskNotesVisibilityProvider.future,
      );
      expect(
        visibleNotes.map((note) => note.noteId),
        unorderedEquals(['authorized-for-b', 'own-note-for-b']),
      );

      final items = await container.read(
        taskListProvider(includeNoteTasks: true).future,
      );
      expect(
        items.where((item) => item.isNote).map((item) => item.note!.noteId),
        unorderedEquals(['authorized-for-b', 'own-note-for-b']),
      );
    },
  );

  test(
    'hides a revoked member task while keeping the owner task visible',
    () async {
      final database = AppDatabase.test();
      final createdAt = DateTime.utc(2026, 9, 15);
      final document = jsonEncode({
        'schemaVersion': 1,
        'blocks': [
          {
            'id': 'owner-task-block',
            'type': 'task',
            'delta': [
              {'insert': 'Tarefa do owner'},
            ],
            'metadata': {'isCompleted': false},
          },
        ],
      });
      await database.notesDao.createNote(
        NotesCompanion.insert(
          id: 'owner-shared-note',
          userId: 'user-a',
          content: 'Nota compartilhada',
          createdAt: createdAt,
          updatedAt: createdAt,
          hasRemoteCopy: const Value(true),
          lifecycleState: const Value(materializedLifecycleState),
          permission: const Value('view'),
        ),
      );
      await database.noteOperationsDao.upsertNoteDocument(
        LocalNoteDocumentsCompanion.insert(
          noteId: 'owner-shared-note',
          revision: 1,
          documentJson: document,
          updatedAt: createdAt,
          materializedDocumentJson: Value(document),
          materializedUpdatedAt: Value(createdAt),
        ),
      );
      await database.userNotePreferencesDao.applyRemotePreference(
        userId: 'user-b',
        noteId: 'owner-shared-note',
        favorite: false,
        archived: false,
        hideCompleted: false,
        collapseImages: false,
        remoteUpdatedAt: createdAt,
      );

      // Catalog reconciliation removes this membership, not the shared note
      // document that the owner still uses.
      await database.userNotePreferencesDao.deletePreference(
        'user-b',
        'owner-shared-note',
      );

      final memberContainer = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          currentUserIdProvider.overrideWithValue('user-b'),
        ],
      );
      final ownerContainer = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          currentUserIdProvider.overrideWithValue('user-a'),
        ],
      );
      addTearDown(() {
        memberContainer.dispose();
        ownerContainer.dispose();
      });
      addTearDown(database.close);

      final memberNotes = memberContainer.listen(
        taskNotesVisibilityProvider,
        (_, _) {},
      );
      final memberTasks = memberContainer.listen(
        taskListProvider(includeNoteTasks: true),
        (_, _) {},
      );
      final ownerNotes = ownerContainer.listen(
        taskNotesVisibilityProvider,
        (_, _) {},
      );
      final ownerTasks = ownerContainer.listen(
        taskListProvider(includeNoteTasks: true),
        (_, _) {},
      );
      addTearDown(() {
        memberNotes.close();
        memberTasks.close();
        ownerNotes.close();
        ownerTasks.close();
      });

      expect(
        await memberContainer.read(taskNotesVisibilityProvider.future),
        isEmpty,
      );
      expect(
        (await memberContainer.read(
          taskListProvider(includeNoteTasks: true).future,
        )).where((item) => item.isNote),
        isEmpty,
      );
      expect(
        (await ownerContainer.read(
          taskNotesVisibilityProvider.future,
        )).map((note) => note.noteId),
        ['owner-shared-note'],
      );
      expect(
        (await ownerContainer.read(
          taskListProvider(includeNoteTasks: true).future,
        )).where((item) => item.isNote).map((item) => item.note!.noteId),
        ['owner-shared-note'],
      );
    },
  );

  test('re-emits the task list at an injected temporal boundary', () async {
    final database = AppDatabase.test();
    var now = DateTime.utc(2026, 9, 15, 23, 59);
    final timers = <_ManualTimer>[];
    await database.tasksDao.insertOrUpdateTask(
      TasksCompanion.insert(
        id: 'tomorrow',
        ownerUserId: 'user-1',
        title: 'Amanhã',
        dueDate: Value(DateTime.utc(2026, 9, 16)),
        createdAt: now,
        updatedAt: now,
      ),
    );
    final provider = taskListProvider(includeNoteTasks: false);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        currentUserIdProvider.overrideWithValue('user-1'),
        taskListClockProvider.overrideWithValue(
          TaskListClock(
            () => now,
            (duration, callback) {
              final timer = _ManualTimer(callback, delay: duration);
              timers.add(timer);
              return timer;
            },
          ),
        ),
      ],
    );
    final values = <List<TaskListItem>>[];
    final subscription = container.listen(provider, (_, next) {
      next.whenData(values.add);
    });
    addTearDown(() {
      subscription.close();
      container.dispose();
    });
    addTearDown(database.close);

    await container.read(provider.future);
    expect(values, hasLength(1));
    expect(timers, hasLength(1));

    now = DateTime.utc(2026, 9, 16);
    timers.first.fire();
    await Future<void>.delayed(Duration.zero);

    expect(values, hasLength(2));
    expect(values.last.single.task!.id, 'tomorrow');
  });

  test(
    'schedules the next civil midnight across a local DST transition',
    () async {
      final database = AppDatabase.test();
      final now = DateTime(2018, 11, 3, 23, 30);
      final expectedBoundary = DateTime(now.year, now.month, now.day + 1);
      final timers = <_ManualTimer>[];
      await database.tasksDao.insertOrUpdateTask(
        TasksCompanion.insert(
          id: 'dst-boundary',
          ownerUserId: 'user-1',
          title: 'Transição DST',
          dueDate: Value(DateTime(2018, 11, 5)),
          createdAt: now,
          updatedAt: now,
        ),
      );
      final provider = taskListProvider(includeNoteTasks: false);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          currentUserIdProvider.overrideWithValue('user-1'),
          taskListClockProvider.overrideWithValue(
            TaskListClock(
              () => now,
              (duration, callback) {
                final timer = _ManualTimer(callback, delay: duration);
                timers.add(timer);
                return timer;
              },
            ),
          ),
        ],
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(() {
        subscription.close();
        container.dispose();
      });
      addTearDown(database.close);

      await container.read(provider.future);

      expect(timers, hasLength(1));
      expect(expectedBoundary.year, now.year);
      expect(expectedBoundary.month, now.month);
      expect(expectedBoundary.day, now.day + 1);
      expect(expectedBoundary.hour, 1);
      expect(expectedBoundary.timeZoneOffset, const Duration(hours: -2));
      expect(timers.single.delay, expectedBoundary.difference(now));
      expect(timers.single.delay, const Duration(minutes: 30));
    },
  );

  test(
    'surfaces malformed effective note documents as a provider error',
    () async {
      final database = AppDatabase.test();
      final createdAt = DateTime.utc(2026, 9, 15);
      await database.notesDao.createNote(
        NotesCompanion.insert(
          id: 'malformed-note',
          userId: 'user-1',
          content: 'Nota ativa',
          createdAt: createdAt,
          updatedAt: createdAt,
          hasRemoteCopy: const Value(true),
        ),
      );
      await database.noteOperationsDao.upsertNoteDocument(
        LocalNoteDocumentsCompanion.insert(
          noteId: 'malformed-note',
          revision: 0,
          documentJson: '{}',
          updatedAt: createdAt,
          materializedDocumentJson: const Value('{malformed'),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          currentUserIdProvider.overrideWithValue('user-1'),
        ],
      );
      final provider = taskListProvider(includeNoteTasks: true);
      final providerError = Completer<Object>();
      final subscription = container.listen(provider, (_, next) {
        if (next.hasError && !providerError.isCompleted) {
          providerError.complete(next.error!);
        }
      });
      addTearDown(() {
        subscription.close();
        container.dispose();
      });
      addTearDown(database.close);

      final error = await providerError.future.timeout(
        const Duration(seconds: 1),
      );
      expect(error, isA<FormatException>());
    },
  );
}

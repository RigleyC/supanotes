import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/connectivity_monitor.dart';
import 'package:supanotes/core/sync/sync_mapper.dart';
import 'package:supanotes/core/sync/sync_repository.dart';
import 'package:supanotes/core/sync/sync_service.dart';
import 'package:supanotes/core/sync/sync_state.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

class FakeSyncRepository implements ISyncRepository {
  bool pushCalled = false;
  Map<String, dynamic>? lastPayload;
  Map<String, dynamic> pullResponse = const {};

  @override
  Future<void> push(Map<String, dynamic> payload) async {
    pushCalled = true;
    lastPayload = payload;
  }

  @override
  Future<Map<String, dynamic>> pull({
    required String lastSyncedAt,
    int limit = 500,
  }) async {
    return pullResponse;
  }
}

class FakeConnectivityMonitor implements ConnectivityMonitor {
  @override
  bool get isConnected => true;

  @override
  Stream<bool> get onConnected => const Stream.empty();

  @override
  Stream<bool> get onConnectivityChanged => const Stream.empty();

  @override
  void dispose() {}
}

void main() {
  group('SyncMapper.noteToJson', () {
    test('serializes note and includes user_id', () {
      final now = DateTime.utc(2026, 6, 15, 12, 0);
      final note = NoteData(
        id: 'note-1',
        userId: 'user-1',
        content: 'Hello World',
        isInbox: false,
        favorite: false,
        archived: false,
        createdAt: now,
        updatedAt: now,
        isDirty: true,
        hasRemoteCopy: false,
        collapseImages: false,
      );

      final json = SyncMapper().noteToJson(note);

      expect(json['user_id'], 'user-1');
      expect(json['content'], 'Hello World');
    });
  });

  group('SyncMapper.taskToJson', () {
    test('serializes recurrence enum as a string', () {
      final now = DateTime.utc(2026, 6, 15, 12, 0);
      final task = TaskData(
        id: 'task-1',
        userId: 'user-1',
        noteId: 'note-1',
        title: 'Buy coffee',
        status: 'open',
        position: 0,
        recurrence: TaskRecurrence.weekly,
        dueDate: now,
        completedAt: null,
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
        isDirty: true,
      );

      final json = SyncMapper().taskToJson(task);

      expect(json['user_id'], 'user-1');
      expect(json['recurrence'], 'weekly');
      expect(json['due_date'], '2026-06-15');
    });

    test('serializes null recurrence as null', () {
      final now = DateTime.utc(2026, 6, 15, 12, 0);
      final task = TaskData(
        id: 'task-1',
        userId: 'user-1',
        noteId: 'note-1',
        title: 'Buy coffee',
        status: 'open',
        position: 0,
        recurrence: null,
        dueDate: null,
        completedAt: null,
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
        isDirty: true,
      );

      final json = SyncMapper().taskToJson(task);

      expect(json['user_id'], 'user-1');
      expect(json['recurrence'], isNull);
      expect(json['due_date'], isNull);
    });
  });

  group('SyncMapper.taskFromJson', () {
    test('treats unknown recurrence strings as null', () {
      final json = {
        'id': 'task-1',
        'user_id': 'user-1',
        'note_id': 'note-1',
        'title': 'Buy coffee',
        'status': 'open',
        'position': 0,
        'recurrence': 'yearly',
        'due_date': null,
        'completed_at': null,
        'created_at': '2026-06-15T12:00:00.000Z',
        'updated_at': '2026-06-15T12:00:00.000Z',
        'deleted_at': null,
      };

      final task = SyncMapper().taskFromJson(json);

      expect(task.recurrence, isNull);
    });

    test('parses YYYY-MM-DD as local midnight (not UTC)', () {
      final json = {
        'id': 'task-1',
        'user_id': 'user-1',
        'note_id': 'note-1',
        'title': 'Buy coffee',
        'status': 'open',
        'position': 0,
        'recurrence': null,
        'due_date': '2026-06-15',
        'completed_at': null,
        'created_at': '2026-06-15T12:00:00.000Z',
        'updated_at': '2026-06-15T12:00:00.000Z',
        'deleted_at': null,
      };

      final task = SyncMapper().taskFromJson(json);

      expect(task.dueDate!.year, 2026);
      expect(task.dueDate!.month, 6);
      expect(task.dueDate!.day, 15);
      expect(task.dueDate!.hour, 0);
    });
  });

  group('SyncService.push', () {
    test(
      'marks pushed notes as having a remote copy and clears dirty flag',
      () async {
        SharedPreferences.setMockInitialValues({});

        final db = AppDatabase.test();
        final dao = db.notesDao;

        final now = DateTime.now().toUtc();
        await dao.createNote(
          NotesCompanion.insert(
            id: 'test-note-1',
            userId: 'test-user',
            content: 'Hello',
            createdAt: now,
            updatedAt: now,
            isDirty: const Value(true),
            hasRemoteCopy: const Value(false),
          ),
        );

        final fakeRepo = FakeSyncRepository();
        final connectivity = FakeConnectivityMonitor();
        final mapper = SyncMapper();
        final notifier = SyncStateNotifier();

        final service = SyncService(
          db: db,
          repo: fakeRepo,
          mapper: mapper,
          connectivity: connectivity,
          notifier: notifier,
          userId: 'test-user',
        );

        await service.push();

        final note = await dao.getNoteById('test-note-1');
        expect(note, isNotNull);
        expect(note!.hasRemoteCopy, isTrue);
        expect(note.isDirty, isFalse);
        expect(fakeRepo.pushCalled, isTrue);

        await db.close();
      },
    );
  });

  group('SyncService.pull', () {
    test(
      'does not overwrite dirty local note fields with stale remote data',
      () async {
        SharedPreferences.setMockInitialValues({});

        final db = AppDatabase.test();
        final now = DateTime.utc(2026, 6, 17, 12);
        await db.notesDao.createNote(
          NotesCompanion.insert(
            id: 'note-1',
            userId: 'test-user',
            content: 'local content',
            createdAt: now,
            updatedAt: now,
            isDirty: const Value(true),
            hasRemoteCopy: const Value(true),
          ),
        );

        final fakeRepo = FakeSyncRepository()
          ..pullResponse = {
            'notes': [
              {
                'id': 'note-1',
                'user_id': 'test-user',
                'context_id': null,
                'title': null,
                'content': 'remote content',
                'excerpt': null,
                'is_inbox': false,
                'favorite': false,
                'archived': false,
                'hide_completed': false,
                'embedding_status': null,
                'shared_permission': null,
                'shared_by_email': null,
                'shared_by_name': null,
                'created_at': now.toIso8601String(),
                'updated_at': now.toIso8601String(),
                'deleted_at': null,
              },
            ],
          };

        final service = SyncService(
          db: db,
          repo: fakeRepo,
          mapper: SyncMapper(),
          connectivity: FakeConnectivityMonitor(),
          notifier: SyncStateNotifier(),
          userId: 'test-user',
        );

        await service.pull();

        final note = await db.notesDao.getNoteById('note-1');
        expect(note, isNotNull);
        expect(note!.content, 'local content');
        expect(note.isDirty, isTrue);

        await db.close();
      },
    );

    test('persists task completions from the remote payload', () async {
      SharedPreferences.setMockInitialValues({});

      final db = AppDatabase.test();
      final completionsDao = db.taskCompletionsDao;

      final completedAt = DateTime.utc(2026, 6, 11, 12, 30);
      final fakeRepo = FakeSyncRepository()
        ..pullResponse = {
          'notes': [],
          'tasks': [],
          'contexts': [],
          'tags': [],
          'task_completions': [
            {
              'id': 'cmp-remote-1',
              'task_id': 'task-1',
              'completed_at': completedAt.toIso8601String(),
              'status': 'completed',
            },
          ],
        };

      final service = SyncService(
        db: db,
        repo: fakeRepo,
        mapper: SyncMapper(),
        connectivity: FakeConnectivityMonitor(),
        notifier: SyncStateNotifier(),
        userId: 'test-user',
      );

      await service.pull();

      final rows = await db.select(db.localTaskCompletions).get();
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.id, 'cmp-remote-1');
      expect(row.taskId, 'task-1');
      expect(row.userId, 'test-user');
      expect(row.completedAt.toUtc(), completedAt);
      expect(row.isDirty, isFalse);

      // Sanity: the unused DAO ref should not leave dangling state.
      expect(completionsDao, isNotNull);

      await db.close();
    });
  });
}

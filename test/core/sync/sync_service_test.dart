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
  group('SyncService.push', () {
    test('marks pushed notes as having a remote copy and clears dirty flag',
        () async {
      SharedPreferences.setMockInitialValues({});

      final db = AppDatabase.test();
      final dao = db.notesDao;

      final now = DateTime.now().toUtc();
      await dao.createNote(NotesCompanion.insert(
        id: 'test-note-1',
        userId: 'test-user',
        content: 'Hello',
        createdAt: now,
        updatedAt: now,
        isDirty: const Value(true),
        hasRemoteCopy: const Value(false),
      ));

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
    });
  });

  group('SyncService.pull', () {
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

      final rows =
          await db.select(db.localTaskCompletions).get();
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

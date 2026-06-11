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
    return {};
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
}

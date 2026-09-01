import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/core/sync/note_outbox_worker.dart';

class _MockSyncService extends Mock implements NoteOperationsSyncService {}

class _CountingOutboxWorker extends NoteOutboxWorker {
  _CountingOutboxWorker()
    : super(
        loadPendingNoteIds: () async => const [],
        syncNote: (_) async => SyncResult.empty(),
        isNoteActive: (_) => false,
      );

  int wakeCount = 0;

  @override
  void wake({bool resetBackoff = true}) {
    wakeCount++;
  }
}

void main() {
  test('unauthenticated state does not construct an outbox worker', () {
    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWith((ref) => null),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(noteOutboxWorkerProvider), isNull);
  });

  test('authenticated worker drains only the current actor outbox', () async {
    final database = AppDatabase.test();
    final syncService = _MockSyncService();
    when(
      () => syncService.syncPending(any()),
    ).thenAnswer((_) async => SyncResult.empty());

    final now = DateTime.utc(2026, 9, 1);
    Future<void> insert({
      required String operationId,
      required String noteId,
      required String ownerUserId,
    }) {
      return database.noteOperationsDao.insertPendingOperation(
        PendingNoteOperationsCompanion.insert(
          operationId: operationId,
          noteId: noteId,
          ownerUserId: Value(ownerUserId),
          baseRevision: 0,
          ordinal: 0,
          kind: 'text_delta',
          payloadJson: '{}',
          createdAt: now,
        ),
      );
    }

    await insert(
      operationId: 'op-a',
      noteId: 'note-a',
      ownerUserId: 'user-a',
    );
    await insert(
      operationId: 'op-b',
      noteId: 'note-b',
      ownerUserId: 'user-b',
    );

    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWith((ref) => 'user-a'),
        appDatabaseProvider.overrideWithValue(database),
        noteOperationsSyncServiceProvider.overrideWithValue(syncService),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    final worker = container.read(noteOutboxWorkerProvider);
    expect(worker, isNotNull);

    await worker!.drain();

    verify(() => syncService.syncPending('note-a')).called(1);
    verifyNever(() => syncService.syncPending('note-b'));
  });

  test('runtime wakes on connectivity and stops resources on dispose', () async {
    final connectivity = StreamController<List<ConnectivityResult>>.broadcast();
    final worker = _CountingOutboxWorker();
    final container = ProviderContainer(
      overrides: [
        noteOutboxWorkerProvider.overrideWithValue(worker),
        noteOutboxConnectivityChangesProvider.overrideWithValue(
          connectivity.stream,
        ),
        noteOutboxSafetyWakeIntervalProvider.overrideWithValue(
          const Duration(milliseconds: 10),
        ),
      ],
    );

    container.read(noteOutboxRuntimeProvider);
    await pumpEventQueue();
    expect(worker.wakeCount, 1, reason: 'runtime performs an initial drain');

    connectivity.add([ConnectivityResult.wifi]);
    await pumpEventQueue();
    expect(worker.wakeCount, 2);

    await Future<void>.delayed(const Duration(milliseconds: 25));
    final countBeforeDispose = worker.wakeCount;
    expect(countBeforeDispose, greaterThan(2), reason: 'safety wake is active');
    expect(connectivity.hasListener, isTrue);

    container.dispose();
    await pumpEventQueue();
    expect(connectivity.hasListener, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 25));
    connectivity.add([ConnectivityResult.wifi]);
    await pumpEventQueue();
    expect(worker.wakeCount, countBeforeDispose);

    await connectivity.close();
    await worker.dispose();
  });
}

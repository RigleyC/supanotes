import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/note_remote_sync_coordinator.dart';
import 'package:supanotes/core/sync/sync_feed_client.dart';
import 'package:supanotes/core/sync/sync_inbox_store.dart';

void main() {
  test('bootstrap snapshots catalog at watermark then catches concurrent changes', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final store = SyncInboxStore(db);
    final fetchAfter = <int>[];
    var catalogPulls = 0;
    var newChangeExists = false;
    final applied = <int>[];

    final coordinator = NoteRemoteSyncCoordinator(
      userId: 'user-1',
      store: store,
      fetchChanges: ({required after, required limit}) async {
        fetchAfter.add(after);
        if (after == 0) {
          return const SyncChangePage(
            cursor: 1,
            watermark: 12,
            hasMore: false,
            changes: [],
          );
        }
        if (after == 12 && newChangeExists) {
          return SyncChangePage(
            cursor: 13,
            watermark: 13,
            hasMore: false,
            changes: [
              SyncChange(
                sequence: 13,
                type: 'note_preferences_changed',
                noteId: 'n1',
                createdAt: DateTime.utc(2026, 9, 2),
              ),
            ],
          );
        }
        return SyncChangePage(
          cursor: after,
          watermark: after,
          hasMore: false,
          changes: const [],
        );
      },
      bootstrapCatalog: () async {
        catalogPulls++;
        newChangeExists = true;
      },
      isNoteActive: (_) => false,
      syncPending: (_) async {},
      confirmedRevision: (_) async => 0,
      pollAndReconcile: (_) async {},
      hydrateRemote: (_) async {},
      deleteLocal: (_) async {},
      onAppliedForTest: (change) => applied.add(change.sequence),
    );

    await coordinator.syncOnce();
    await coordinator.syncOnce();

    expect(catalogPulls, 1);
    expect(fetchAfter.take(2), [0, 12]);
    expect(applied, [13]);
    expect(await store.isBootstrapComplete('user-1'), isTrue);
    expect(await store.getCursor('user-1'), 13);
  });

  test('note change drains local outbox before polling and hydration', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final store = SyncInboxStore(db);
    await store.completeBootstrap(userId: 'user-1', cursor: 0);
    final calls = <String>[];

    final coordinator = NoteRemoteSyncCoordinator(
      userId: 'user-1',
      store: store,
      fetchChanges: ({required after, required limit}) async => SyncChangePage(
        cursor: 4,
        watermark: 4,
        hasMore: false,
        changes: [
          SyncChange(
            sequence: 4,
            type: 'note_changed',
            noteId: 'n1',
            revision: 8,
            createdAt: DateTime.utc(2026, 9, 2),
          ),
        ],
      ),
      bootstrapCatalog: () async {},
      isNoteActive: (_) => false,
      syncPending: (id) async => calls.add('outbox:$id'),
      confirmedRevision: (_) async => 6,
      pollAndReconcile: (id) async => calls.add('poll:$id'),
      hydrateRemote: (id) async => calls.add('hydrate:$id'),
      deleteLocal: (_) async {},
    );

    await coordinator.syncOnce();

    expect(calls, ['outbox:n1', 'poll:n1', 'hydrate:n1']);
  });

  test('deleted and revoked notes are removed without hydration', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final store = SyncInboxStore(db);
    await store.completeBootstrap(userId: 'user-1', cursor: 0);
    final deleted = <String>[];
    var hydrated = 0;

    final coordinator = NoteRemoteSyncCoordinator(
      userId: 'user-1',
      store: store,
      fetchChanges: ({required after, required limit}) async => SyncChangePage(
        cursor: 2,
        watermark: 2,
        hasMore: false,
        changes: [
          SyncChange(sequence: 1, type: 'note_deleted', noteId: 'n1', createdAt: DateTime.utc(2026, 9, 2)),
          SyncChange(sequence: 2, type: 'note_access_revoked', noteId: 'n2', createdAt: DateTime.utc(2026, 9, 2)),
        ],
      ),
      bootstrapCatalog: () async {},
      isNoteActive: (_) => false,
      syncPending: (_) async {},
      confirmedRevision: (_) async => null,
      pollAndReconcile: (_) async {},
      hydrateRemote: (_) async => hydrated++,
      deleteLocal: (id) async => deleted.add(id),
    );

    await coordinator.syncOnce();

    expect(deleted, ['n1', 'n2']);
    expect(hydrated, 0);
  });
}

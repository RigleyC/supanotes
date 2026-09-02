import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/sync_feed_client.dart';
import 'package:supanotes/core/sync/sync_inbox_store.dart';

void main() {
  test('ingest persists cursor and deduplicates changes transactionally', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final store = SyncInboxStore(db);
    await store.initialize();

    final page = SyncChangePage(
      cursor: 2,
      hasMore: false,
      changes: [
        SyncChange(sequence: 1, type: 'note_changed', noteId: 'n1', revision: 3, createdAt: DateTime.utc(2026, 9, 1)),
        SyncChange(sequence: 2, type: 'note_preferences_changed', noteId: 'n2', createdAt: DateTime.utc(2026, 9, 1)),
      ],
    );

    await store.ingestPage(userId: 'u1', page: page);
    await store.ingestPage(userId: 'u1', page: page);

    expect(await store.getCursor('u1'), 2);
    expect(await store.isBootstrapComplete('u1'), isFalse);
    final pending = await store.listPending('u1');
    expect(pending.map((e) => e.sequence).toList(), [1, 2]);
  });

  test('bootstrap is completed only by explicit catalog checkpoint', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final store = SyncInboxStore(db);

    await store.ingestPage(
      userId: 'u1',
      page: SyncChangePage(
        cursor: 4,
        hasMore: false,
        changes: const [],
      ),
    );
    expect(await store.isBootstrapComplete('u1'), isFalse);

    await store.completeBootstrap(userId: 'u1', cursor: 9);
    expect(await store.isBootstrapComplete('u1'), isTrue);
    expect(await store.getCursor('u1'), 9);
  });

  test('pending inbox survives store recreation and applied events do not return', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    var store = SyncInboxStore(db);
    await store.initialize();
    await store.ingestPage(
      userId: 'u1',
      page: SyncChangePage(
        cursor: 8,
        hasMore: false,
        changes: [
          SyncChange(sequence: 8, type: 'note_changed', noteId: 'n1', revision: 4, createdAt: DateTime.utc(2026, 9, 1)),
        ],
      ),
    );

    store = SyncInboxStore(db);
    await store.initialize();
    expect((await store.listPending('u1')).single.sequence, 8);
    await store.markApplied(userId: 'u1', sequence: 8);
    expect(await store.listPending('u1'), isEmpty);
    expect(await store.getCursor('u1'), 8);
  });
}

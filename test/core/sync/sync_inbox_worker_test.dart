import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/sync_feed_client.dart';
import 'package:supanotes/core/sync/sync_inbox_store.dart';
import 'package:supanotes/core/sync/sync_inbox_worker.dart';

void main() {
  test('fetches pages, persists them, then applies in sequence order', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final store = SyncInboxStore(db);
    final applied = <int>[];
    var calls = 0;
    final worker = SyncInboxWorker(
      userId: 'u1',
      store: store,
      fetchChanges: ({required after, required limit}) async {
        calls++;
        return SyncChangePage(
          cursor: 2,
          hasMore: false,
          changes: [
            SyncChange(sequence: 1, type: 'note_changed', noteId: 'n1', createdAt: DateTime.utc(2026, 9, 1)),
            SyncChange(sequence: 2, type: 'note_changed', noteId: 'n2', createdAt: DateTime.utc(2026, 9, 1)),
          ],
        );
      },
      isNoteActive: (_) => false,
      applyChange: (change) async => applied.add(change.sequence),
    );

    await worker.syncOnce();

    expect(calls, 1);
    expect(applied, [1, 2]);
    expect(await store.getCursor('u1'), 2);
    expect(await store.listPending('u1'), isEmpty);
  });

  test('active note stays durable in inbox until a later drain', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final store = SyncInboxStore(db);
    var active = true;
    var applied = 0;
    final worker = SyncInboxWorker(
      userId: 'u1',
      store: store,
      fetchChanges: ({required after, required limit}) async => SyncChangePage(
        cursor: 3,
        hasMore: false,
        changes: [
          SyncChange(sequence: 3, type: 'note_changed', noteId: 'n1', createdAt: DateTime.utc(2026, 9, 1)),
        ],
      ),
      isNoteActive: (_) => active,
      applyChange: (_) async => applied++,
    );

    await worker.syncOnce();
    expect(applied, 0);
    expect((await store.listPending('u1')).single.sequence, 3);

    active = false;
    await worker.drainInbox();
    expect(applied, 1);
    expect(await store.listPending('u1'), isEmpty);
  });

  test('persisted inbox is applied after worker recreation without refetching old page', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final store = SyncInboxStore(db);
    await store.initialize();
    await store.ingestPage(
      userId: 'u1',
      page: SyncChangePage(
        cursor: 9,
        hasMore: false,
        changes: [
          SyncChange(sequence: 9, type: 'note_access_revoked', noteId: 'n9', createdAt: DateTime.utc(2026, 9, 1)),
        ],
      ),
    );

    final applied = <int>[];
    final worker = SyncInboxWorker(
      userId: 'u1',
      store: SyncInboxStore(db),
      fetchChanges: ({required after, required limit}) async => SyncChangePage(cursor: after, hasMore: false, changes: const []),
      isNoteActive: (_) => false,
      applyChange: (change) async => applied.add(change.sequence),
    );

    await worker.syncOnce();
    expect(applied, [9]);
    expect(await store.getCursor('u1'), 9);
  });
}

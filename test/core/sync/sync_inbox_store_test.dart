import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/sync_feed_client.dart';
import 'package:supanotes/core/sync/sync_inbox_store.dart';

void main() {
  test(
    'v30 inbox tables migrate to the typed Drift schema without data loss',
    () async {
      final db = AppDatabase.test();
      addTearDown(db.close);

      await db.customStatement('DROP TABLE sync_inbox');
      await db.customStatement('DROP TABLE sync_feed_cursors');
      await db.customStatement('''
      CREATE TABLE sync_feed_cursors (
        user_id TEXT PRIMARY KEY,
        receive_cursor INTEGER NOT NULL DEFAULT 0,
        bootstrap_complete INTEGER NOT NULL DEFAULT 0
      )
    ''');
      await db.customStatement('''
      CREATE TABLE sync_inbox (
        user_id TEXT NOT NULL,
        sequence INTEGER NOT NULL,
        type TEXT NOT NULL,
        note_id TEXT,
        revision INTEGER,
        created_at TEXT NOT NULL,
        applied_at TEXT,
        PRIMARY KEY (user_id, sequence)
      )
    ''');
      await db.customStatement('''
      INSERT INTO sync_feed_cursors(user_id, receive_cursor, bootstrap_complete)
      VALUES ('u1', 12, 1)
    ''');
      await db.customStatement('''
      INSERT INTO sync_inbox(user_id, sequence, type, note_id, revision, created_at)
      VALUES ('u1', 12, 'note_changed', 'n1', 4, '2026-09-02T12:00:00.000Z')
    ''');

      await db.migration.onUpgrade(Migrator(db), 30, 31);

      final store = SyncInboxStore(db);
      expect(await store.getCursor('u1'), 12);
      expect(await store.isBootstrapComplete('u1'), isTrue);
      final pending = await store.listPending('u1');
      expect(pending.single.noteId, 'n1');
      expect(pending.single.taskId, equals(null));
      expect(pending.single.createdAt, DateTime.utc(2026, 9, 2, 12));
    },
  );

  test(
    'v31 databases receive feed columns before the store queries them',
    () async {
      final db = AppDatabase.test();
      addTearDown(db.close);

      await db.customStatement('DROP TABLE sync_inbox');
      await db.customStatement('DROP TABLE sync_feed_cursors');
      await db.customStatement('''
        CREATE TABLE sync_feed_cursors (
          user_id TEXT PRIMARY KEY,
          receive_cursor INTEGER NOT NULL DEFAULT 0,
          bootstrap_complete INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.customStatement('''
        CREATE TABLE sync_inbox (
          user_id TEXT NOT NULL,
          sequence INTEGER NOT NULL,
          type TEXT NOT NULL,
          note_id TEXT,
          revision INTEGER,
          created_at INTEGER NOT NULL,
          applied_at INTEGER,
          PRIMARY KEY (user_id, sequence)
        )
      ''');
      await db.customStatement('''
        INSERT INTO sync_feed_cursors(user_id, receive_cursor, bootstrap_complete)
        VALUES ('u1', 7, 1)
      ''');
      await db.customStatement('''
        INSERT INTO sync_inbox(
          user_id, sequence, type, note_id, revision, created_at
        ) VALUES ('u1', 7, 'note_changed', 'n1', 3, 0)
      ''');

      await db.migration.onUpgrade(Migrator(db), 31, 32);

      final store = SyncInboxStore(db);
      expect(await store.getCursor('u1'), 7);
      expect(await store.getBootstrapVersion('u1'), 0);
      expect((await store.listPending('u1')).single.taskId, equals(null));
      final cursorColumns = await db
          .customSelect('PRAGMA table_info(sync_feed_cursors)')
          .get();
      final inboxColumns = await db
          .customSelect('PRAGMA table_info(sync_inbox)')
          .get();
      expect(
        cursorColumns.any(
          (column) => column.data['name'] == 'bootstrap_version',
        ),
        isTrue,
      );
      expect(
        inboxColumns.any((column) => column.data['name'] == 'task_id'),
        isTrue,
      );
    },
  );

  test(
    'ingest persists cursor and deduplicates changes transactionally',
    () async {
      final db = AppDatabase.test();
      addTearDown(db.close);
      final store = SyncInboxStore(db);
      final page = SyncChangePage(
        cursor: 3,
        hasMore: false,
        changes: [
          SyncChange(
            sequence: 1,
            type: 'note_changed',
            noteId: 'n1',
            revision: 3,
            createdAt: DateTime.utc(2026, 9, 1),
          ),
          SyncChange(
            sequence: 2,
            type: 'note_preferences_changed',
            noteId: 'n2',
            createdAt: DateTime.utc(2026, 9, 1),
          ),
          SyncChange(
            sequence: 3,
            type: 'task_changed',
            taskId: 'task-1',
            createdAt: DateTime.utc(2026, 9, 1),
          ),
        ],
      );

      await store.ingestPage(userId: 'u1', page: page);
      await store.ingestPage(userId: 'u1', page: page);

      expect(await store.getCursor('u1'), 3);
      expect(await store.isBootstrapComplete('u1'), isFalse);
      final pending = await store.listPending('u1');
      expect(pending.map((e) => e.sequence).toList(), [1, 2, 3]);
      expect(pending.last.taskId, 'task-1');
    },
  );

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
    expect(await store.getBootstrapVersion('u1'), 0);

    await store.completeBootstrap(
      userId: 'u1',
      cursor: 8,
      bootstrapVersion: 2,
    );
    expect(await store.getCursor('u1'), 9);
    expect(await store.getBootstrapVersion('u1'), 2);
  });

  test('snapshot writes and cursor checkpoint roll back together', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final store = SyncInboxStore(db);

    await expectLater(
      store.completeBootstrap(
        userId: 'u1',
        cursor: 12,
        bootstrapVersion: 2,
        applySnapshotInTransaction: () async {
          await db
              .into(db.syncInbox)
              .insert(
                SyncInboxCompanion.insert(
                  userId: 'u1',
                  sequence: 12,
                  type: 'task_changed',
                  taskId: const Value('task-1'),
                  createdAt: DateTime.utc(2026, 9, 2),
                ),
              );
          throw StateError('snapshot failed');
        },
      ),
      throwsStateError,
    );

    expect(await store.getCursor('u1'), 0);
    expect(await store.getBootstrapVersion('u1'), 0);
    expect(await store.listPending('u1'), isEmpty);
  });

  test(
    'pending inbox survives store recreation and applied events do not return',
    () async {
      final db = AppDatabase.test();
      addTearDown(db.close);
      var store = SyncInboxStore(db);
      await store.ingestPage(
        userId: 'u1',
        page: SyncChangePage(
          cursor: 8,
          hasMore: false,
          changes: [
            SyncChange(
              sequence: 8,
              type: 'note_changed',
              noteId: 'n1',
              revision: 4,
              createdAt: DateTime.utc(2026, 9, 1),
            ),
          ],
        ),
      );

      store = SyncInboxStore(db);
      expect((await store.listPending('u1')).single.sequence, 8);
      await store.markApplied(userId: 'u1', sequence: 8);
      expect(await store.listPending('u1'), isEmpty);
      expect(await store.getCursor('u1'), 8);
    },
  );
}

import 'package:drift/drift.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/sync_feed_client.dart';

final class SyncInboxEntry {
  const SyncInboxEntry({
    required this.userId,
    required this.sequence,
    required this.type,
    required this.createdAt,
    this.noteId,
    this.revision,
  });

  final String userId;
  final int sequence;
  final String type;
  final String? noteId;
  final int? revision;
  final DateTime createdAt;
}

final class SyncInboxStore {
  SyncInboxStore(this._database);

  final AppDatabase _database;
  Future<void>? _initialization;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    await _database.customStatement('''
      CREATE TABLE IF NOT EXISTS sync_feed_cursors (
        user_id TEXT PRIMARY KEY,
        receive_cursor INTEGER NOT NULL DEFAULT 0,
        bootstrap_complete INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await _database.customStatement('''
      CREATE TABLE IF NOT EXISTS sync_inbox (
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
    await _database.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_sync_inbox_pending
      ON sync_inbox(user_id, applied_at, sequence)
    ''');
  }

  Future<int> getCursor(String userId) async {
    await initialize();
    final row = await _database.customSelect(
      'SELECT receive_cursor FROM sync_feed_cursors WHERE user_id = ?',
      variables: [Variable.withString(userId)],
    ).getSingleOrNull();
    return row?.read<int>('receive_cursor') ?? 0;
  }

  Future<bool> isBootstrapComplete(String userId) async {
    await initialize();
    final row = await _database.customSelect(
      'SELECT bootstrap_complete FROM sync_feed_cursors WHERE user_id = ?',
      variables: [Variable.withString(userId)],
    ).getSingleOrNull();
    return (row?.read<int>('bootstrap_complete') ?? 0) != 0;
  }

  Future<void> completeBootstrap({
    required String userId,
    required int cursor,
  }) async {
    await initialize();
    await _database.customStatement(
      '''
      INSERT INTO sync_feed_cursors(user_id, receive_cursor, bootstrap_complete)
      VALUES (?, ?, 1)
      ON CONFLICT(user_id) DO UPDATE SET
        receive_cursor = MAX(sync_feed_cursors.receive_cursor, excluded.receive_cursor),
        bootstrap_complete = 1
      ''',
      [userId, cursor],
    );
  }

  Future<void> ingestPage({
    required String userId,
    required SyncChangePage page,
  }) async {
    await initialize();
    await _database.transaction(() async {
      for (final change in page.changes) {
        await _database.customStatement(
          '''
          INSERT OR IGNORE INTO sync_inbox(
            user_id, sequence, type, note_id, revision, created_at
          ) VALUES (?, ?, ?, ?, ?, ?)
          ''',
          [
            userId,
            change.sequence,
            change.type,
            change.noteId,
            change.revision,
            change.createdAt.toUtc().toIso8601String(),
          ],
        );
      }
      await _database.customStatement(
        '''
        INSERT INTO sync_feed_cursors(user_id, receive_cursor, bootstrap_complete)
        VALUES (?, ?, 0)
        ON CONFLICT(user_id) DO UPDATE SET
          receive_cursor = MAX(sync_feed_cursors.receive_cursor, excluded.receive_cursor)
        ''',
        [userId, page.cursor],
      );
    });
  }

  Future<List<SyncInboxEntry>> listPending(String userId) async {
    await initialize();
    final rows = await _database.customSelect(
      '''
      SELECT user_id, sequence, type, note_id, revision, created_at
      FROM sync_inbox
      WHERE user_id = ? AND applied_at IS NULL
      ORDER BY sequence ASC
      ''',
      variables: [Variable.withString(userId)],
    ).get();
    return rows.map((row) {
      return SyncInboxEntry(
        userId: row.read<String>('user_id'),
        sequence: row.read<int>('sequence'),
        type: row.read<String>('type'),
        noteId: row.readNullable<String>('note_id'),
        revision: row.readNullable<int>('revision'),
        createdAt: DateTime.parse(row.read<String>('created_at')).toUtc(),
      );
    }).toList(growable: false);
  }

  Future<void> markApplied({
    required String userId,
    required int sequence,
  }) async {
    await initialize();
    await _database.customStatement(
      '''
      UPDATE sync_inbox
      SET applied_at = ?
      WHERE user_id = ? AND sequence = ? AND applied_at IS NULL
      ''',
      [DateTime.now().toUtc().toIso8601String(), userId, sequence],
    );
  }

  Future<void> clearAll() async {
    await initialize();
    await _database.transaction(() async {
      await _database.customStatement('DELETE FROM sync_inbox');
      await _database.customStatement('DELETE FROM sync_feed_cursors');
    });
  }
}

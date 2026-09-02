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

/// Durable receive-side state for the account-scoped sync change feed.
///
/// The tables are part of [AppDatabase]'s schema and migrations. Keeping the
/// store as a small repository preserves the feed workers' API without hiding
/// schema creation in runtime SQL.
final class SyncInboxStore {
  SyncInboxStore(this._database);

  final AppDatabase _database;

  Future<int> getCursor(String userId) async {
    final row = await (_database.select(
      _database.syncFeedCursors,
    )..where((t) => t.userId.equals(userId))).getSingleOrNull();
    return row?.receiveCursor ?? 0;
  }

  Future<bool> isBootstrapComplete(String userId) async {
    final row = await (_database.select(
      _database.syncFeedCursors,
    )..where((t) => t.userId.equals(userId))).getSingleOrNull();
    return row?.bootstrapComplete ?? false;
  }

  Future<void> completeBootstrap({
    required String userId,
    required int cursor,
  }) async {
    await _database.transaction(() async {
      final current = await (_database.select(
        _database.syncFeedCursors,
      )..where((t) => t.userId.equals(userId))).getSingleOrNull();
      await _database
          .into(_database.syncFeedCursors)
          .insertOnConflictUpdate(
            SyncFeedCursorsCompanion.insert(
              userId: userId,
              receiveCursor: Value(_maxCursor(current?.receiveCursor, cursor)),
              bootstrapComplete: const Value(true),
            ),
          );
    });
  }

  Future<void> ingestPage({
    required String userId,
    required SyncChangePage page,
  }) async {
    await _database.transaction(() async {
      for (final change in page.changes) {
        await _database
            .into(_database.syncInbox)
            .insert(
              SyncInboxCompanion.insert(
                userId: userId,
                sequence: change.sequence,
                type: change.type,
                noteId: Value(change.noteId),
                revision: Value(change.revision),
                createdAt: change.createdAt.toUtc(),
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }

      final current = await (_database.select(
        _database.syncFeedCursors,
      )..where((t) => t.userId.equals(userId))).getSingleOrNull();
      await _database
          .into(_database.syncFeedCursors)
          .insertOnConflictUpdate(
            SyncFeedCursorsCompanion.insert(
              userId: userId,
              receiveCursor: Value(
                _maxCursor(current?.receiveCursor, page.cursor),
              ),
              bootstrapComplete: Value(current?.bootstrapComplete ?? false),
            ),
          );
    });
  }

  Future<List<SyncInboxEntry>> listPending(String userId) async {
    final rows =
        await (_database.select(_database.syncInbox)
              ..where((t) => t.userId.equals(userId) & t.appliedAt.isNull())
              ..orderBy([(t) => OrderingTerm.asc(t.sequence)]))
            .get();
    return rows
        .map(
          (row) => SyncInboxEntry(
            userId: row.userId,
            sequence: row.sequence,
            type: row.type,
            noteId: row.noteId,
            revision: row.revision,
            createdAt: row.createdAt.toUtc(),
          ),
        )
        .toList(growable: false);
  }

  Future<void> markApplied({
    required String userId,
    required int sequence,
  }) async {
    await (_database.update(_database.syncInbox)..where(
          (t) =>
              t.userId.equals(userId) &
              t.sequence.equals(sequence) &
              t.appliedAt.isNull(),
        ))
        .write(SyncInboxCompanion(appliedAt: Value(DateTime.now().toUtc())));
  }

  Future<void> clearAll() async {
    await _database.transaction(() async {
      await _database.delete(_database.syncInbox).go();
      await _database.delete(_database.syncFeedCursors).go();
    });
  }

  int _maxCursor(int? current, int candidate) =>
      current == null || candidate > current ? candidate : current;
}

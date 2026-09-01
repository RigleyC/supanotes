import 'package:drift/drift.dart';
import 'package:supanotes/core/database/daos/note_operations_dao.dart';

extension NoteOperationsPendingQuery on NoteOperationsDao {
  Future<List<String>> getPendingNoteIds({
    required String ownerUserId,
  }) async {
    final db = attachedDatabase;
    final query = db.select(db.pendingNoteOperations)
      ..where(
        (row) =>
            row.ownerUserId.equals(ownerUserId) &
            (row.status.equals('pending') | row.status.equals('in_flight')),
      )
      ..orderBy([(row) => OrderingTerm(expression: row.noteId)]);

    final noteIds = await query.map((row) => row.noteId).get();
    return noteIds.toSet().toList()..sort();
  }
}

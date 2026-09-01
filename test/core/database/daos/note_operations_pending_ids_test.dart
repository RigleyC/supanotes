import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/database/database.dart';

void main() {
  test('lists distinct pending and in-flight note ids scoped to owner', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final now = DateTime.utc(2026, 9, 1);

    Future<void> insert({
      required String operationId,
      required String noteId,
      required String owner,
      required int ordinal,
      String status = 'pending',
    }) {
      return db.noteOperationsDao.insertPendingOperation(
        PendingNoteOperationsCompanion.insert(
          operationId: operationId,
          noteId: noteId,
          ownerUserId: Value(owner),
          baseRevision: ordinal,
          ordinal: ordinal,
          kind: 'text_delta',
          payloadJson: '{}',
          createdAt: now,
          status: Value(status),
        ),
      );
    }

    await insert(
      operationId: 'a-1',
      noteId: 'note-b',
      owner: 'user-a',
      ordinal: 0,
    );
    await insert(
      operationId: 'a-2',
      noteId: 'note-b',
      owner: 'user-a',
      ordinal: 1,
      status: 'in_flight',
    );
    await insert(
      operationId: 'a-3',
      noteId: 'note-a',
      owner: 'user-a',
      ordinal: 0,
    );
    await insert(
      operationId: 'b-1',
      noteId: 'note-z',
      owner: 'user-b',
      ordinal: 0,
    );
    await insert(
      operationId: 'a-ignored',
      noteId: 'note-complete',
      owner: 'user-a',
      ordinal: 0,
      status: 'accepted',
    );

    final ids = await db.noteOperationsDao.getPendingNoteIds(
      ownerUserId: 'user-a',
    );

    expect(ids, ['note-a', 'note-b']);
  });
}

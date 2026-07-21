import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:supanotes/core/database/database.dart';

void main() {
  group('NoteOperationsDao', () {
    test('upsert and watch note document', () async {
      final db = AppDatabase.test();
      final now = DateTime.utc(2026, 7, 20);

      await db.noteOperationsDao.upsertNoteDocument(
        LocalNoteDocumentsCompanion.insert(
          noteId: 'note-1',
          revision: 5,
          documentJson: '{"blocks": []}',
          updatedAt: now,
        ),
      );

      final doc = await db.noteOperationsDao.watchNoteDocument('note-1').first;
      expect(doc, isNotNull);
      expect(doc!.noteId, 'note-1');
      expect(doc.revision, 5);
      expect(doc.documentJson, '{"blocks": []}');

      await db.close();
    });

    test('upsertNoteDocument replaces existing row', () async {
      final db = AppDatabase.test();
      final now = DateTime.utc(2026, 7, 20);

      await db.noteOperationsDao.upsertNoteDocument(
        LocalNoteDocumentsCompanion.insert(
          noteId: 'note-1',
          revision: 1,
          documentJson: '{"v": 1}',
          updatedAt: now,
        ),
      );
      await db.noteOperationsDao.upsertNoteDocument(
        LocalNoteDocumentsCompanion.insert(
          noteId: 'note-1',
          revision: 2,
          documentJson: '{"v": 2}',
          updatedAt: now,
        ),
      );

      final docs = await db.select(db.localNoteDocuments).get();
      expect(docs, hasLength(1));
      expect(docs.single.revision, 2);

      await db.close();
    });

    test('deleteNoteDocument removes the row', () async {
      final db = AppDatabase.test();
      final now = DateTime.utc(2026, 7, 20);

      await db.noteOperationsDao.upsertNoteDocument(
        LocalNoteDocumentsCompanion.insert(
          noteId: 'note-1',
          revision: 1,
          documentJson: '{}',
          updatedAt: now,
        ),
      );
      await db.noteOperationsDao.deleteNoteDocument('note-1');

      final doc = await db.noteOperationsDao.watchNoteDocument('note-1').first;
      expect(doc, isNull);

      await db.close();
    });

    test('insert and watch pending operations ordered by ordinal', () async {
      final db = AppDatabase.test();
      final now = DateTime.utc(2026, 7, 20);

      await db.noteOperationsDao.insertPendingOperation(
        PendingNoteOperationsCompanion.insert(
          operationId: 'op-2',
          noteId: 'note-1',
          baseRevision: 1,
          ordinal: 1,
          kind: 'text_delta',
          blockId: const Value('block-1'),
          payloadJson: '{}',
          createdAt: now,
        ),
      );
      await db.noteOperationsDao.insertPendingOperation(
        PendingNoteOperationsCompanion.insert(
          operationId: 'op-1',
          noteId: 'note-1',
          baseRevision: 0,
          ordinal: 0,
          kind: 'create_block',
          payloadJson: '{}',
          createdAt: now,
        ),
      );

      final ops = await db.noteOperationsDao
          .watchPendingOperations('note-1')
          .first;
      expect(ops, hasLength(2));
      expect(ops[0].ordinal, 0);
      expect(ops[0].operationId, 'op-1');
      expect(ops[1].ordinal, 1);
      expect(ops[1].operationId, 'op-2');

      await db.close();
    });

    test('deletePendingOperation removes matching row', () async {
      final db = AppDatabase.test();
      final now = DateTime.utc(2026, 7, 20);

      await db.noteOperationsDao.insertPendingOperation(
        PendingNoteOperationsCompanion.insert(
          operationId: 'op-1',
          noteId: 'note-1',
          baseRevision: 0,
          ordinal: 0,
          kind: 'create_block',
          payloadJson: '{}',
          createdAt: now,
        ),
      );
      await db.noteOperationsDao.deletePendingOperation('op-1');

      final ops = await db.noteOperationsDao.getPendingOperations('note-1');
      expect(ops, isEmpty);

      await db.close();
    });

    test('deletePendingOperationsForNote removes all ops for note', () async {
      final db = AppDatabase.test();
      final now = DateTime.utc(2026, 7, 20);

      await db.noteOperationsDao.insertPendingOperation(
        PendingNoteOperationsCompanion.insert(
          operationId: 'op-1',
          noteId: 'note-1',
          baseRevision: 0,
          ordinal: 0,
          kind: 'create_block',
          payloadJson: '{}',
          createdAt: now,
        ),
      );
      await db.noteOperationsDao.insertPendingOperation(
        PendingNoteOperationsCompanion.insert(
          operationId: 'op-2',
          noteId: 'note-1',
          baseRevision: 1,
          ordinal: 1,
          kind: 'text_delta',
          payloadJson: '{}',
          createdAt: now,
        ),
      );
      await db.noteOperationsDao.insertPendingOperation(
        PendingNoteOperationsCompanion.insert(
          operationId: 'op-3',
          noteId: 'note-2',
          baseRevision: 0,
          ordinal: 0,
          kind: 'create_block',
          payloadJson: '{}',
          createdAt: now,
        ),
      );

      await db.noteOperationsDao.deletePendingOperationsForNote('note-1');

      final opsNote1 = await db.noteOperationsDao.getPendingOperations('note-1');
      expect(opsNote1, isEmpty);

      final opsNote2 = await db.noteOperationsDao.getPendingOperations('note-2');
      expect(opsNote2, hasLength(1));

      await db.close();
    });

    test('incrementAttempt updates attempt count and timestamp', () async {
      final db = AppDatabase.test();
      final now = DateTime.utc(2026, 7, 20);

      await db.noteOperationsDao.insertPendingOperation(
        PendingNoteOperationsCompanion.insert(
          operationId: 'op-1',
          noteId: 'note-1',
          baseRevision: 0,
          ordinal: 0,
          kind: 'create_block',
          payloadJson: '{}',
          createdAt: now,
        ),
      );

      await db.noteOperationsDao.incrementAttempt('op-1');

      final ops = await db.noteOperationsDao.getPendingOperations('note-1');
      expect(ops, hasLength(1));
      expect(ops.single.attemptCount, 1);
      expect(ops.single.lastAttemptAt, isNotNull);

      await db.close();
    });

    test('insert and watch sync errors', () async {
      final db = AppDatabase.test();
      final now = DateTime.utc(2026, 7, 20);

      await db.noteOperationsDao.insertSyncError(
        NoteSyncErrorsCompanion.insert(
          operationId: 'err-1',
          noteId: 'note-1',
          errorCode: 'INVALID_DELTA',
          message: 'Bad delta',
          payloadJson: '{}',
          createdAt: now,
        ),
      );

      final errors =
          await db.noteOperationsDao.watchSyncErrors('note-1').first;
      expect(errors, hasLength(1));
      expect(errors.single.errorCode, 'INVALID_DELTA');

      await db.close();
    });

    test('deleteSyncError removes matching error', () async {
      final db = AppDatabase.test();
      final now = DateTime.utc(2026, 7, 20);

      await db.noteOperationsDao.insertSyncError(
        NoteSyncErrorsCompanion.insert(
          operationId: 'err-1',
          noteId: 'note-1',
          errorCode: 'INVALID_DELTA',
          message: 'Bad delta',
          payloadJson: '{}',
          createdAt: now,
        ),
      );
      await db.noteOperationsDao.deleteSyncError('err-1');

      final errors =
          await db.noteOperationsDao.watchSyncErrors('note-1').first;
      expect(errors, isEmpty);

      await db.close();
    });
  });
}

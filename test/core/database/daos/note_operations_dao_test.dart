import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/database/note_lifecycle_policy.dart';

void main() {
  group('NoteOperationsDao', () {
    test('upsert and watch note document', () async {
      final db = AppDatabase.test();
      final now = DateTime.utc(2026, 7, 20);

      await db.notesDao.createNote(
        NotesCompanion.insert(
          id: 'note-1',
          userId: 'user-1',
          content: '',
          createdAt: now,
          updatedAt: now,
        ),
      );

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
      expect(
        (await db.notesDao.getNoteById('note-1'))!.lifecycleState,
        materializedLifecycleState,
      );

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

    test(
      'saveMaterializedDocument projects content and excerpt to notes table',
      () async {
        final db = AppDatabase.test();
        final now = DateTime.utc(2026, 7, 20);

        await db.notesDao.createNote(
          NotesCompanion.insert(
            id: 'note-1',
            userId: 'user-1',
            content: '',
            createdAt: now,
            updatedAt: now,
          ),
        );

        const docJson =
            '{"schemaVersion":1,"blocks":[{"id":"b1","type":"header1","delta":[{"insert":"Lista de Mercado"}]},{"id":"b2","type":"task","delta":[{"insert":"Comprar leite"}]}]}';

        await db.noteOperationsDao.saveMaterializedDocument(
          noteId: 'note-1',
          documentJson: docJson,
          content: 'Lista de Mercado\nComprar leite',
          excerpt: 'Lista de Mercado\nComprar leite',
          updatedAt: now,
        );

        final note = await db.notesDao.getNoteWithPrefsById('note-1', 'user-1');
        expect(note, isNotNull);
        expect(note!.note.content, contains('Lista de Mercado'));
        expect(note.title, 'Lista de Mercado');
        expect(note.note.lifecycleState, materializedLifecycleState);

        await db.close();
      },
    );

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

    test(
      'reusing an operation id with a different payload is rejected',
      () async {
        final db = AppDatabase.test();
        final now = DateTime.utc(2026, 7, 20);
        final original = PendingNoteOperationsCompanion.insert(
          operationId: 'op-reused',
          noteId: 'note-1',
          baseRevision: 0,
          ordinal: 0,
          kind: 'create_block',
          payloadJson: '{"text":"first"}',
          createdAt: now,
        );

        await db.noteOperationsDao.insertPendingOperation(original);
        await db.noteOperationsDao.insertPendingOperation(original);
        await expectLater(
          db.noteOperationsDao.insertPendingOperation(
            PendingNoteOperationsCompanion.insert(
              operationId: 'op-reused',
              noteId: 'note-1',
              baseRevision: 0,
              ordinal: 0,
              kind: 'create_block',
              payloadJson: '{"text":"different"}',
              createdAt: now,
            ),
          ),
          throwsA(isA<StateError>()),
        );

        final rows = await db.noteOperationsDao.getPendingOperations('note-1');
        expect(rows, hasLength(1));
        expect(rows.single.payloadJson, '{"text":"first"}');
        await db.close();
      },
    );

    test(
      'batch insert is idempotent for existing rows and persists new rows',
      () async {
        final db = AppDatabase.test();
        final now = DateTime.utc(2026, 7, 20);
        final existing = PendingNoteOperationsCompanion.insert(
          operationId: 'op-existing',
          noteId: 'note-1',
          baseRevision: 0,
          ordinal: 0,
          kind: 'create_block',
          payloadJson: '{"text":"existing"}',
          createdAt: now,
        );
        await db.noteOperationsDao.insertPendingOperation(existing);

        await db.noteOperationsDao.runInTransaction(
          () => db.noteOperationsDao.insertPendingOperationsInTransaction([
            existing,
            PendingNoteOperationsCompanion.insert(
              operationId: 'op-new-1',
              noteId: 'note-1',
              baseRevision: 1,
              ordinal: 1,
              kind: 'text_delta',
              payloadJson: '{}',
              createdAt: now,
            ),
            PendingNoteOperationsCompanion.insert(
              operationId: 'op-new-2',
              noteId: 'note-1',
              baseRevision: 2,
              ordinal: 2,
              kind: 'text_delta',
              payloadJson: '{"delta":[]}',
              createdAt: now,
            ),
          ]),
        );

        final rows = await db.noteOperationsDao.getPendingOperations('note-1');
        expect(rows.map((row) => row.operationId), [
          'op-existing',
          'op-new-1',
          'op-new-2',
        ]);
        expect(rows.first.payloadJson, '{"text":"existing"}');
        await db.close();
      },
    );

    test(
      'batch payload reuse failure does not partially insert new rows',
      () async {
        final db = AppDatabase.test();
        final now = DateTime.utc(2026, 7, 20);
        await db.noteOperationsDao.insertPendingOperation(
          PendingNoteOperationsCompanion.insert(
            operationId: 'op-existing',
            noteId: 'note-1',
            baseRevision: 0,
            ordinal: 0,
            kind: 'create_block',
            payloadJson: '{"text":"existing"}',
            createdAt: now,
          ),
        );

        await expectLater(
          db.noteOperationsDao.runInTransaction(
            () => db.noteOperationsDao.insertPendingOperationsInTransaction([
              PendingNoteOperationsCompanion.insert(
                operationId: 'op-existing',
                noteId: 'note-1',
                baseRevision: 0,
                ordinal: 0,
                kind: 'create_block',
                payloadJson: '{"text":"changed"}',
                createdAt: now,
              ),
              PendingNoteOperationsCompanion.insert(
                operationId: 'op-not-written',
                noteId: 'note-1',
                baseRevision: 1,
                ordinal: 1,
                kind: 'text_delta',
                payloadJson: '{}',
                createdAt: now,
              ),
            ]),
          ),
          throwsA(isA<StateError>()),
        );

        final rows = await db.noteOperationsDao.getPendingOperations('note-1');
        expect(rows.map((row) => row.operationId), ['op-existing']);
        await db.close();
      },
    );

    test('a failed transaction rolls back a pending operation batch', () async {
      final db = AppDatabase.test();
      final now = DateTime.utc(2026, 7, 20);

      await expectLater(
        db.noteOperationsDao.runInTransaction(() async {
          await db.noteOperationsDao.insertPendingOperationsInTransaction([
            PendingNoteOperationsCompanion.insert(
              operationId: 'op-rollback',
              noteId: 'note-1',
              baseRevision: 0,
              ordinal: 0,
              kind: 'create_block',
              payloadJson: '{}',
              createdAt: now,
            ),
          ]);
          throw StateError('fail after write');
        }),
        throwsA(isA<StateError>()),
      );

      expect(
        await db.noteOperationsDao.getPendingOperations('note-1'),
        isEmpty,
      );
      await db.close();
    });

    test(
      'account-scoped pending operations do not cross user boundaries',
      () async {
        final db = AppDatabase.test();
        final now = DateTime.utc(2026, 7, 20);

        await db.noteOperationsDao.insertPendingOperation(
          PendingNoteOperationsCompanion.insert(
            operationId: 'op-a',
            noteId: 'shared-note',
            ownerUserId: const Value('user-a'),
            baseRevision: 0,
            ordinal: 0,
            kind: 'text_delta',
            payloadJson: '{}',
            createdAt: now,
          ),
        );
        await db.noteOperationsDao.insertPendingOperation(
          PendingNoteOperationsCompanion.insert(
            operationId: 'op-b',
            noteId: 'shared-note',
            ownerUserId: const Value('user-b'),
            baseRevision: 0,
            ordinal: 0,
            kind: 'text_delta',
            payloadJson: '{}',
            createdAt: now,
          ),
        );

        final userA = await db.noteOperationsDao.getPendingOperations(
          'shared-note',
          ownerUserId: 'user-a',
        );
        final userB = await db.noteOperationsDao.getPendingOperations(
          'shared-note',
          ownerUserId: 'user-b',
        );

        expect(userA.map((op) => op.operationId), ['op-a']);
        expect(userB.map((op) => op.operationId), ['op-b']);

        await db.close();
      },
    );

    test(
      'legacy rows can be adopted only after local ownership is proven',
      () async {
        final db = AppDatabase.test();
        final now = DateTime.utc(2026, 7, 20);

        await db.notesDao.createNote(
          NotesCompanion.insert(
            id: 'owned-note',
            userId: 'user-a',
            content: 'local note',
            createdAt: now,
            updatedAt: now,
          ),
        );
        await db.noteOperationsDao.insertPendingOperation(
          PendingNoteOperationsCompanion.insert(
            operationId: 'legacy-op',
            noteId: 'owned-note',
            baseRevision: 0,
            ordinal: 0,
            kind: 'text_delta',
            payloadJson: '{}',
            createdAt: now,
          ),
        );

        expect(
          await db.noteOperationsDao.getPendingOperations(
            'owned-note',
            ownerUserId: 'user-a',
          ),
          isEmpty,
        );

        expect(
          await db.noteOperationsDao.getNoteOwnerId('owned-note'),
          'user-a',
        );
        await db.noteOperationsDao.adoptLegacyRows('owned-note', 'user-a');

        final adopted = await db.noteOperationsDao.getPendingOperations(
          'owned-note',
          ownerUserId: 'user-a',
        );
        expect(adopted.map((op) => op.operationId), ['legacy-op']);

        await db.close();
      },
    );

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

      final opsNote1 = await db.noteOperationsDao.getPendingOperations(
        'note-1',
      );
      expect(opsNote1, isEmpty);

      final opsNote2 = await db.noteOperationsDao.getPendingOperations(
        'note-2',
      );
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

      final errors = await db.noteOperationsDao.watchSyncErrors('note-1').first;
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

      final errors = await db.noteOperationsDao.watchSyncErrors('note-1').first;
      expect(errors, isEmpty);

      await db.close();
    });

    test('sync errors can be queried by account owner', () async {
      final db = AppDatabase.test();
      final now = DateTime.utc(2026, 7, 20);

      for (final owner in ['user-a', 'user-b']) {
        await db.noteOperationsDao.insertSyncError(
          NoteSyncErrorsCompanion.insert(
            operationId: 'err-$owner',
            noteId: 'note-1',
            ownerUserId: Value(owner),
            errorCode: 'NETWORK',
            message: 'offline',
            payloadJson: '{}',
            createdAt: now,
          ),
        );
      }

      expect(
        await db.noteOperationsDao.getSyncErrorCount(
          'note-1',
          ownerUserId: 'user-a',
        ),
        1,
      );
      expect(
        await db.noteOperationsDao
            .watchSyncErrors('note-1', ownerUserId: 'user-b')
            .first,
        hasLength(1),
      );

      await db.close();
    });
  });
}

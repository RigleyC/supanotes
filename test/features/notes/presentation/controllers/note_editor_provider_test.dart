import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/database/note_lifecycle_policy.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/notes/attachments/data/attachments_repository.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_provider.dart';
import 'package:supanotes/features/notes/editor/sync/note_session_coordinator.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';
import 'package:super_editor/super_editor.dart';

class _MockNoteSyncClient extends Mock implements NoteSyncClient {}

class _MockApiClient extends Mock implements ApiClient {}

class _MockAttachmentsRepository extends Mock
    implements AttachmentsRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> buildContainer({
    AppDatabase? database,
    NoteSyncClient? syncClient,
    ApiClient? apiClient,
    bool registerTearDown = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = database ?? AppDatabase.test();
    if (registerTearDown) addTearDown(db.close);

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        currentUserIdProvider.overrideWithValue('user-1'),
        noteSyncClientProvider.overrideWithValue(
          syncClient ?? _MockNoteSyncClient(),
        ),
        apiClientProvider.overrideWithValue(apiClient ?? _MockApiClient()),
        attachmentsRepositoryProvider.overrideWithValue(
          _MockAttachmentsRepository(),
        ),
      ],
    );
    if (registerTearDown) addTearDown(container.dispose);
    return container;
  }

  Future<void> insertNote(
    AppDatabase db, {
    required String id,
    String content = '',
    String? permission,
  }) async {
    final now = DateTime.utc(2026, 7, 26);
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: id,
            userId: 'user-1',
            content: content,
            createdAt: now,
            updatedAt: now,
            isDirty: const Value(false),
            permission: Value(permission),
          ),
        );
  }

  test(
    'canonical view note receives sync but does not capture local operations',
    () async {
      final container = await buildContainer();
      final db = container.read(appDatabaseProvider);
      await insertNote(db, id: 'note-view', permission: 'view');

      final session = await container.read(
        noteEditorSessionProvider('note-view').future,
      );

      expect(session.syncSession, isNotNull);
      expect(session.captureLocalOperations, isFalse);
    },
  );

  test('canonical edit note captures local operations', () async {
    final container = await buildContainer();
    final db = container.read(appDatabaseProvider);
    await insertNote(db, id: 'note-edit');

    final session = await container.read(
      noteEditorSessionProvider('note-edit').future,
    );

    expect(session.captureLocalOperations, isTrue);
  });

  test(
    'closing immediately after an edit keeps the note out of draft discard',
    () async {
      final container = await buildContainer();
      final db = container.read(appDatabaseProvider);
      await insertNote(db, id: 'note-close-before-debounce');

      final session = await container.read(
        noteEditorSessionProvider('note-close-before-debounce').future,
      );
      session.controller.editor.execute([
        InsertTextRequest(
          documentPosition: const DocumentPosition(
            nodeId: 'init',
            nodePosition: TextNodePosition(offset: 0),
          ),
          textToInsert: 'typed before close',
          attributions: const {},
        ),
      ]);

      await container
          .read(noteSessionCoordinatorProvider)
          .close('note-close-before-debounce');

      final discarded = await db.noteLifecycleDao.discardLocalDraftIfUntouched(
        'note-close-before-debounce',
      );
      final note = await db.notesDao.getNoteById('note-close-before-debounce');

      expect(discarded, isFalse);
      expect(note, isNotNull);
      expect(note!.lifecycleState, materializedLifecycleState);
    },
  );

  test(
    'opens the hydrated local document through the real editor session',
    () async {
      final container = await buildContainer();
      final db = container.read(appDatabaseProvider);
      await insertNote(
        db,
        id: 'note-local-first',
        content: 'Local first frame',
      );
      await db.noteOperationsDao.upsertNoteDocument(
        LocalNoteDocumentsCompanion.insert(
          noteId: 'note-local-first',
          revision: 4,
          documentJson: jsonEncode(const {
            'schemaVersion': 1,
            'blocks': [
              {
                'id': 'local-block',
                'type': 'paragraph',
                'delta': [
                  {'insert': 'Local first frame'},
                ],
                'metadata': {},
              },
            ],
          }),
          updatedAt: DateTime.utc(2026, 8, 3),
        ),
      );

      final session = await container.read(
        noteEditorSessionProvider('note-local-first').future,
      );

      expect(
        (session.controller.document.first as TextNode).text.toPlainText(),
        'Local first frame',
      );
    },
  );

  test(
    'reopens the hydrated local document after restart without network access',
    () async {
      final file = File(
        '${Directory.systemTemp.path}/supanotes-editor-${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      final client = _MockNoteSyncClient();
      final firstDatabase = AppDatabase.test(executor: NativeDatabase(file));
      final firstContainer = await buildContainer(
        database: firstDatabase,
        syncClient: client,
        registerTearDown: false,
      );

      await insertNote(
        firstDatabase,
        id: 'note-restart-local',
        content: 'Restarted local content',
      );
      await firstDatabase.noteOperationsDao.upsertNoteDocument(
        LocalNoteDocumentsCompanion.insert(
          noteId: 'note-restart-local',
          revision: 7,
          documentJson: jsonEncode(const {
            'schemaVersion': 1,
            'blocks': [
              {
                'id': 'restart-block',
                'type': 'paragraph',
                'delta': [
                  {'insert': 'Restarted local content'},
                ],
                'metadata': {},
              },
            ],
          }),
          updatedAt: DateTime.utc(2026, 8, 3),
        ),
      );

      final firstSession = await firstContainer.read(
        noteEditorSessionProvider('note-restart-local').future,
      );
      expect(
        (firstSession.controller.document.first as TextNode).text.toPlainText(),
        'Restarted local content',
      );
      firstContainer.dispose();
      await firstDatabase.close();

      final secondDatabase = AppDatabase.test(executor: NativeDatabase(file));
      final secondContainer = await buildContainer(
        database: secondDatabase,
        syncClient: client,
        registerTearDown: false,
      );
      addTearDown(() async {
        secondContainer.dispose();
        await secondDatabase.close();
        if (file.existsSync()) await file.delete();
      });

      final secondSession = await secondContainer.read(
        noteEditorSessionProvider('note-restart-local').future,
      );
      await pumpEventQueue();

      expect(
        (secondSession.controller.document.first as TextNode).text
            .toPlainText(),
        'Restarted local content',
      );
      verifyNever(() => client.getDocument('note-restart-local'));
    },
  );

  test(
    'open session stops capturing when note permission becomes view',
    () async {
      final container = await buildContainer();
      final db = container.read(appDatabaseProvider);
      await insertNote(db, id: 'note-permission');
      final provider = noteEditorSessionProvider('note-permission');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);

      final session = await container.read(provider.future);
      expect(session.captureLocalOperations, isTrue);

      await (db.update(db.notes)
            ..where((note) => note.id.equals('note-permission')))
          .write(const NotesCompanion(permission: Value('view')));
      await pumpEventQueue();

      expect(session.captureLocalOperations, isFalse);
    },
  );

  test('open session stops capturing when the note is removed', () async {
    final container = await buildContainer();
    final db = container.read(appDatabaseProvider);
    await insertNote(db, id: 'note-removed');
    final provider = noteEditorSessionProvider('note-removed');
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);

    final session = await container.read(provider.future);
    expect(session.captureLocalOperations, isTrue);

    await (db.delete(
      db.notes,
    )..where((note) => note.id.equals('note-removed'))).go();
    await pumpEventQueue();

    expect(session.captureLocalOperations, isFalse);
  });

  test(
    'repeated calls for the same note share the exact same canonical session',
    () async {
      final container = await buildContainer();

      final firstSession = await container.read(
        noteEditorSessionProvider('note-shared-owner').future,
      );

      final secondSession = await container.read(
        noteEditorSessionProvider('note-shared-owner').future,
      );

      expect(identical(firstSession, secondSession), isTrue);
      expect(firstSession.noteId, equals('note-shared-owner'));
    },
  );

  test(
    'disposing container during async note fetch closes session cleanly',
    () async {
      final container = await buildContainer();
      final coordinator = container.read(noteSessionCoordinatorProvider);

      final future = container.read(
        noteEditorSessionProvider('note-race-test').future,
      );
      container.dispose();

      expect(future, throwsStateError);
      expect(coordinator.statusOf('note-race-test'), NoteSessionStatus.closed);
    },
  );
}

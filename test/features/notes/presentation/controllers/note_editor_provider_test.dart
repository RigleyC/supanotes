import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/notes/data/attachments_repository.dart';
import 'package:supanotes/features/notes/data/note_sync_client.dart';
import 'package:supanotes/features/notes/domain/note_session_coordinator.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_provider.dart';

class _MockNoteSyncClient extends Mock implements NoteSyncClient {}

class _MockAttachmentsRepository extends Mock
    implements AttachmentsRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> buildContainer() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.test();
    addTearDown(db.close);

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        currentUserIdProvider.overrideWithValue('user-1'),
        noteSyncClientProvider.overrideWithValue(_MockNoteSyncClient()),
        attachmentsRepositoryProvider.overrideWithValue(
          _MockAttachmentsRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> insertNote(
    AppDatabase db, {
    required String id,
    String? permission,
  }) async {
    final now = DateTime.utc(2026, 7, 26);
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: id,
            userId: 'user-1',
            content: '',
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

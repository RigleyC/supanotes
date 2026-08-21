import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/auth/domain/user.dart';
import 'package:supanotes/features/auth/presentation/controllers/auth_controller.dart';
import 'package:supanotes/features/notes/catalog/data/note_catalog_sync.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';

class _StubAuthController extends AuthController {
  @override
  Future<User?> build() async =>
      const User(id: 'user-1', email: 'user@example.com', name: 'User');
}

class _MockNoteSyncClient extends Mock implements NoteSyncClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('authenticated catalog provider hydrates a remote note', () async {
    final database = AppDatabase.test();
    final client = _MockNoteSyncClient();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        noteSyncClientProvider.overrideWithValue(client),
        authControllerProvider.overrideWith(_StubAuthController.new),
      ],
    );
    final completed = Completer<void>();

    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    when(client.listNotes).thenAnswer(
      (_) async => [
        {
          'id': 'remote-note',
          'user_id': 'user-1',
          'created_at': '2026-08-01T12:00:00.000Z',
          'updated_at': '2026-08-01T12:00:00.000Z',
          'collapse_images': false,
        },
      ],
    );
    when(() => client.getDocument('remote-note')).thenAnswer(
      (_) async => NoteDocumentResponse(
        noteId: 'remote-note',
        revision: 1,
        document: const {'schemaVersion': 1, 'blocks': []},
        serverTime: DateTime.utc(2026, 8, 1, 12),
      ),
    );

    final subscription = container.listen(noteCatalogSyncProvider, (_, next) {
      if (next.hasError) {
        completed.completeError(
          next.error!,
          next.stackTrace ?? StackTrace.current,
        );
      } else if (next.hasValue && !completed.isCompleted) {
        completed.complete();
      }
    });
    addTearDown(subscription.close);

    await completed.future.timeout(const Duration(seconds: 2));

    final note = await database.notesDao.getNoteById('remote-note');
    expect(note, isNotNull);
    expect(note!.userId, 'user-1');
    expect(note.hasRemoteCopy, isTrue);
    verify(client.listNotes).called(1);
    verify(() => client.getDocument('remote-note')).called(1);
  });
}

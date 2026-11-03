import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/notes/catalog/data/notes_repository.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_provider.dart';
import 'package:supanotes/features/notes/editor/sync/note_session_handle.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';

/// Server double that answers like the real backend for a note it has never
/// seen: reads are forbidden.
class _ServerWithoutTheNote implements NoteSyncClient {
  final calls = <String>[];

  @override
  Future<OperationsListResponse> getOperationsSince(
    String noteId,
    int sinceRevision, {
    int? limit,
  }) async {
    calls.add('getOperationsSince');
    throw NoteOperationsException(
      errorCode: 'FORBIDDEN',
      message: 'forbidden',
      statusCode: 403,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName.toString());
    return super.noSuchMethod(invocation);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Regression: opening a brand-new note and not typing made the first poll
  // (~2s) ask the server about a note that only existed locally. The 403 was
  // treated as a revoked permission and the editor switched to read-only,
  // dropping the keyboard and making the note impossible to focus again.
  test('an untouched local-only note stays editable after polling', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final database = AppDatabase.test();
    final server = _ServerWithoutTheNote();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentUserIdProvider.overrideWithValue('user-1'),
        noteSyncClientProvider.overrideWithValue(server),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await database.close();
    });

    await container.read(notesRepositoryProvider).createLocalNote(id: 'n1');
    container.listen(noteEditorSessionProvider('n1'), (_, _) {});
    final session = await container.read(
      noteEditorSessionProvider('n1').future,
    );

    // Two poll intervals.
    await Future<void>.delayed(const Duration(milliseconds: 4500));

    expect(server.calls, isNot(contains('getOperationsSince')));
    expect(session.captureLocalOperations, isTrue);
    expect(session.status, isNot(NoteSessionStatus.error));
  }, timeout: const Timeout(Duration(seconds: 30)));
}

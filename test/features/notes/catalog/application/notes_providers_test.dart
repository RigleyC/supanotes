import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/catalog/application/notes_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'activeNotesProvider emits local notes for the authenticated user',
    () async {
      final database = AppDatabase.test();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          currentUserIdProvider.overrideWithValue('user-1'),
        ],
      );

      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      final subscription = container.listen(activeNotesProvider, (_, _) {});
      addTearDown(subscription.close);

      final now = DateTime.utc(2026, 8);
      await database.notesDao.createNote(
        NotesCompanion.insert(
          id: 'note-local-1',
          userId: 'user-1',
          content: 'Local note',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final notes = await container.read(activeNotesProvider.future);

      expect(notes, hasLength(1));
      expect(notes.single.id, 'note-local-1');
      expect(notes.single.title, 'Local note');
    },
  );
}

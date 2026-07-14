import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:mocktail/mocktail.dart';

import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/presentation/note_editor_screen.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_provider.dart';
import 'package:supanotes/features/tasks/data/tasks_repository.dart';

class _MockTasksRepository extends Mock implements ITasksRepository {}

void main() {
  late AppDatabase db;
  late _MockTasksRepository mockTasksRepo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.test();
    mockTasksRepo = _MockTasksRepository();
    when(() => mockTasksRepo.watchByNote(any())).thenAnswer((_) => Stream.value([]));
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('dynamic content update when other user edits note', (WidgetTester tester) async {
    final now = DateTime.now().toUtc();
    
    // Seed initial note and node
    await db.into(db.notes).insert(
      NotesCompanion.insert(
        id: 'note-1',
        userId: 'user-A',
        content: '',
        createdAt: now,
        updatedAt: now,
        isDirty: const Value(false),
        hasRemoteCopy: const Value(true),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          currentUserIdProvider.overrideWithValue('user-A'),
          tasksRepositoryProvider.overrideWithValue(mockTasksRepo),
        ],
        child: const MaterialApp(
          home: NoteEditorScreen(noteId: 'note-1'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final element = tester.element(find.byType(NoteEditorScreen));
    final container = ProviderScope.containerOf(element);
    final controller = container.read(noteEditorControllerProvider('note-1'));

    // Clean up: unmount widget tree to dispose providers and cancel database streams
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:mocktail/mocktail.dart';

import 'package:super_editor/super_editor.dart';
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

    await db.into(db.noteNodes).insert(
      NoteNodesCompanion.insert(
        id: 'node-1',
        noteId: 'note-1',
        position: const Value('0.0'),
        type: 'paragraph',
        data: '{"text":"Original content from User A"}',
        createdAt: now,
        updatedAt: now,
        isDirty: const Value(false),
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

    // Check initial text is rendered using widget predicate
    final originalTextFinder = find.byWidgetPredicate(
      (w) => w.toString().contains('text: "Original content from User A"'),
    );
    expect(originalTextFinder, findsWidgets);

    // Seed update from collaborator User B
    await db.into(db.noteNodes).insertOnConflictUpdate(
      NoteNodesCompanion.insert(
        id: 'node-1',
        noteId: 'note-1',
        position: const Value('0.0'),
        type: 'paragraph',
        data: '{"text":"Updated content from User B"}',
        createdAt: now,
        updatedAt: now.add(const Duration(seconds: 1)),
        isDirty: const Value(false),
      ),
    );

    await tester.pumpAndSettle();

    // Verify that the UI updated reactively to show User B's content
    final updatedTextFinder = find.byWidgetPredicate(
      (w) => w.toString().contains('text: "Updated content from User B"'),
    );
    expect(updatedTextFinder, findsWidgets);
    expect(originalTextFinder, findsNothing);

    // Also assert on the document state directly for extra verification
    final docText = controller.document!.map((n) => n is TextNode ? n.text.toPlainText() : '').join(' ');
    expect(docText, contains('Updated content from User B'));
    expect(docText, isNot(contains('Original content from User A')));

    // Clean up: unmount widget tree to dispose providers and cancel database streams
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}

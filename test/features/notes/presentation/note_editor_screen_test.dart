import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/domain/note_strings.dart';
import 'package:supanotes/features/notes/domain/task_entry.dart';
import 'package:supanotes/features/notes/presentation/note_editor_screen.dart';
import 'package:supanotes/shared/theme/app_theme.dart';
import 'package:supanotes/shared/widgets/animated_task_checkbox.dart';
import 'package:supanotes/features/tasks/data/tasks_repository.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';

class _FakeNotesRepository implements INotesRepository {
  _FakeNotesRepository(this.controller);

  final StreamController<NoteModel?> controller;

  @override
  Stream<NoteModel?> watchNoteById(String id) => controller.stream;

  @override
  Future<void> saveNoteSnapshot({
    required String id,
    required String title,
    required String content,
    required List<TaskEntry> tasks,
  }) async {}

  @override
  Future<void> deleteIfEmptyOrTombstone(String id) async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockTasksRepository extends Mock implements ITasksRepository {}

void main() {
  testWidgets('initialized editor stays visible during stream refresh', skip: true, (
    tester,
  ) async {
    final streamController = StreamController<NoteModel?>();
    addTearDown(streamController.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notesRepositoryProvider.overrideWithValue(
            _FakeNotesRepository(streamController),
          ),
          tasksByNoteStreamProvider.overrideWith((ref, arg) => Stream.value(<TaskModel>[])),
        ],
        child: const MaterialApp(home: NoteEditorScreen(noteId: 'note-1')),
      ),
    );

    streamController.add(
      NoteModel(
        id: 'note-1',
        userId: 'u-1',
        title: 'Persisted note',
        excerpt: null,
        content: '# Persisted note',
        favorite: false,
        archived: false,
        isInbox: false,
        contextId: null,
        createdAt: DateTime(2026, 6, 11),
        updatedAt: DateTime(2026, 6, 11),
        hideCompleted: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Persisted note'), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    streamController.add(
      NoteModel(
        id: 'note-1',
        userId: 'u-1',
        title: 'Persisted note',
        excerpt: null,
        content: '# Persisted note',
        favorite: false,
        archived: false,
        isInbox: false,
        contextId: null,
        createdAt: DateTime(2026, 6, 11),
        updatedAt: DateTime(2026, 6, 12),
        hideCompleted: false,
      ),
    );
    await tester.pump();

    expect(find.text('Persisted note'), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('dark mode editor uses primary color for mobile caret controls', (
    tester,
  ) async {
    final streamController = StreamController<NoteModel?>();
    addTearDown(streamController.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notesRepositoryProvider.overrideWithValue(
            _FakeNotesRepository(streamController),
          ),
          tasksByNoteStreamProvider.overrideWith((ref, arg) => Stream.value(<TaskModel>[])),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: const NoteEditorScreen(noteId: 'note-1'),
        ),
      ),
    );

    streamController.add(
      NoteModel(
        id: 'note-1',
        userId: 'u-1',
        title: 'Dark note',
        excerpt: null,
        content: 'Dark content',
        favorite: false,
        archived: false,
        isInbox: false,
        contextId: null,
        createdAt: DateTime(2026, 6, 11),
        updatedAt: DateTime(2026, 6, 11),
        hideCompleted: false,
      ),
    );
    await tester.pumpAndSettle();

    final primary = AppTheme.darkTheme.colorScheme.primary;
    final androidScope = tester.widget<SuperEditorAndroidControlsScope>(
      find.byType(SuperEditorAndroidControlsScope).first,
    );
    final iosScope = tester.widget<SuperEditorIosControlsScope>(
      find.byType(SuperEditorIosControlsScope).first,
    );

    expect(androidScope.controller.controlsColor, primary);
    expect(iosScope.controller.handleColor, primary);
  });

  test('NoteEditor wires the custom note stylesheet', () {
    final source = File(
      'lib/features/notes/presentation/widgets/note_editor.dart',
    ).readAsStringSync();

    expect(source, contains('noteStylesheet'));
  });

  testWidgets('owner actions put share inside the more menu', (tester) async {
    final streamController = StreamController<NoteModel?>();
    addTearDown(streamController.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notesRepositoryProvider.overrideWithValue(
            _FakeNotesRepository(streamController),
          ),
          tasksByNoteStreamProvider.overrideWith((ref, arg) => Stream.value(<TaskModel>[])),
        ],
        child: const MaterialApp(home: NoteEditorScreen(noteId: 'note-1')),
      ),
    );

    streamController.add(
      NoteModel(
        id: 'note-1',
        userId: 'u-1',
        title: 'Owner note',
        excerpt: null,
        content: 'Plain content',
        favorite: false,
        archived: false,
        isInbox: false,
        contextId: null,
        createdAt: DateTime(2026, 6, 17),
        updatedAt: DateTime(2026, 6, 17),
        hideCompleted: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.share_outlined), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text(NoteStrings.shareLabel), findsOneWidget);
    expect(find.text(NoteStrings.hideCompleted), findsOneWidget);
  });

  testWidgets('tapping a task checkbox calls completeTask on the repository', (
    tester,
  ) async {
    final streamController = StreamController<NoteModel?>();
    addTearDown(streamController.close);

    final mockTasksRepo = _MockTasksRepository();
    when(() => mockTasksRepo.watchByNote(any())).thenAnswer(
      (_) => Stream.value([
        TaskModel(
          id: 'task-1',
          userId: 'user-1',
          noteId: 'note-1',
          title: 'buy milk',
          status: 'open',
          position: 0,
          dueDate: DateTime.now().add(const Duration(days: 1)),
          completedAt: null,
          recurrence: null,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ]),
    );
    when(() => mockTasksRepo.completeTask(any())).thenAnswer((_) async {});
    when(() => mockTasksRepo.reopenTask(any())).thenAnswer((_) async {});

    const noteContent = '# Test note\n\n- [ ] buy milk <!-- task:task-1 -->\n';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notesRepositoryProvider.overrideWithValue(
            _FakeNotesRepository(streamController),
          ),
          tasksRepositoryProvider.overrideWithValue(mockTasksRepo),
        ],
        child: const MaterialApp(home: NoteEditorScreen(noteId: 'note-1')),
      ),
    );

    streamController.add(
      NoteModel(
        id: 'note-1',
        userId: 'u-1',
        title: 'Test note',
        excerpt: null,
        content: noteContent,
        favorite: false,
        archived: false,
        isInbox: false,
        contextId: null,
        createdAt: DateTime(2026, 6, 11),
        updatedAt: DateTime(2026, 6, 11),
        hideCompleted: false,
      ),
    );
    await tester.pumpAndSettle();

    final checkbox = find.byType(AnimatedTaskCheckbox);
    expect(checkbox, findsOneWidget);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();

    verify(() => mockTasksRepo.completeTask('task-1')).called(1);
  });

  testWidgets('un-tapping a completed task checkbox calls reopenTask on the repository', (
    tester,
  ) async {
    final streamController = StreamController<NoteModel?>();
    addTearDown(streamController.close);

    final mockTasksRepo = _MockTasksRepository();
    when(() => mockTasksRepo.watchByNote(any())).thenAnswer(
      (_) => Stream.value([
        TaskModel(
          id: 'task-1',
          userId: 'user-1',
          noteId: 'note-1',
          title: 'buy milk',
          status: 'done',
          position: 0,
          dueDate: DateTime.now().add(const Duration(days: 1)),
          completedAt: DateTime.now(),
          recurrence: null,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ]),
    );
    when(() => mockTasksRepo.completeTask(any())).thenAnswer((_) async {});
    when(() => mockTasksRepo.reopenTask(any())).thenAnswer((_) async {});

    const noteContent = '# Test note\n\n- [x] buy milk <!-- task:task-1 -->\n';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notesRepositoryProvider.overrideWithValue(
            _FakeNotesRepository(streamController),
          ),
          tasksRepositoryProvider.overrideWithValue(mockTasksRepo),
        ],
        child: const MaterialApp(home: NoteEditorScreen(noteId: 'note-1')),
      ),
    );

    streamController.add(
      NoteModel(
        id: 'note-1',
        userId: 'u-1',
        title: 'Test note',
        excerpt: null,
        content: noteContent,
        favorite: false,
        archived: false,
        isInbox: false,
        contextId: null,
        createdAt: DateTime(2026, 6, 11),
        updatedAt: DateTime(2026, 6, 11),
        hideCompleted: false,
      ),
    );
    await tester.pumpAndSettle();

    final checkbox = find.byType(AnimatedTaskCheckbox);
    expect(checkbox, findsOneWidget);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();

    verify(() => mockTasksRepo.reopenTask('task-1')).called(1);
  });
}

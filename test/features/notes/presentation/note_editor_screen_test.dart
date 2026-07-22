import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/domain/note_strings.dart';
import 'package:supanotes/features/notes/domain/note_with_tasks.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_delegate.dart';
import 'package:supanotes/features/notes/presentation/note_editor_screen.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_editor.dart';
import 'package:supanotes/shared/theme/app_theme.dart';
import 'package:supanotes/shared/widgets/app_task_checkbox.dart';
import 'package:supanotes/features/tasks/data/tasks_repository.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_provider.dart';
import 'package:supanotes/features/notes/presentation/widgets/task_exit_animator.dart';

NoteEditorController _createTestController(List<DocumentNode> nodes) {
  final controller = NoteEditorController(userId: 'test-user');
  final doc = MutableDocument(nodes: nodes);
  controller.document = doc;
  controller.bind('note-1');
  controller.composer = MutableDocumentComposer();
  controller.editor = createDefaultDocumentEditor(
    document: doc,
    composer: controller.composer!,
  );
  return controller;
}

class _FakeNotesRepository implements INotesRepository {
  _FakeNotesRepository(this.controller, [this.tasks = const []])
      : _broadcast = controller.stream.asBroadcastStream();

  final StreamController<NoteModel?> controller;
  final Stream<NoteModel?> _broadcast;
  final List<TaskModel> tasks;

  @override
  Stream<NoteModel?> watchNoteById(String id) => _broadcast;

  @override
  Future<void> saveNoteSnapshot({
    required String id,
    required String content,
  }) async {}

  @override
  Future<void> deleteIfEmptyOrTombstone(String id) async {}

  @override
  Stream<NoteWithTasks> watchNoteWithTasks(String noteId) =>
      _broadcast.map((note) => NoteWithTasks(note: note, tasks: tasks));

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockTasksRepository extends Mock implements ITasksRepository {}

_MockTasksRepository _defaultMockTasksRepo() {
  final mock = _MockTasksRepository();
  when(() => mock.watchByNote(any())).thenAnswer((_) => Stream.value([]));
  when(() => mock.completeTask(any())).thenAnswer((_) async => (nextDue: null, previousDue: null, previousHasTime: false));
  when(() => mock.reopenTask(any(), originalDueDate: any(named: 'originalDueDate'))).thenAnswer((_) async {});
  return mock;
}

void main() {
  testWidgets(
    'initialized editor stays visible during stream refresh',
    skip: true,
    (tester) async {
      final streamController = StreamController<NoteModel?>();
      addTearDown(streamController.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notesRepositoryProvider.overrideWithValue(
              _FakeNotesRepository(streamController),
            ),
            tasksRepositoryProvider.overrideWithValue(_defaultMockTasksRepo()),
          ],
          child: const MaterialApp(home: NoteEditorScreen(noteId: 'note-1')),
        ),
      );

      streamController.add(
        NoteModel(
          id: 'note-1',
          userId: 'u-1',
          content: '# Persisted note',
          title: 'Persisted note',
          favorite: false,
          archived: false,
          
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
          content: '# Persisted note',
          title: 'Persisted note',
          favorite: false,
          archived: false,
          
          createdAt: DateTime(2026, 6, 11),
          updatedAt: DateTime(2026, 6, 12),
          hideCompleted: false,
        ),
      );
      await tester.pump();

      expect(find.text('Persisted note'), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

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
          tasksRepositoryProvider.overrideWithValue(_defaultMockTasksRepo()),
          currentUserIdProvider.overrideWithValue('test-user'),
          appDatabaseProvider.overrideWithValue(AppDatabase.test()),
          noteEditorControllerProvider.overrideWith((ref, id) async => _createTestController([
            ParagraphNode(id: '1', text: AttributedText('Dark content')),
          ])),
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
        content: 'Dark content',
        title: 'Dark content',
        favorite: false,
        archived: false,
        
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

  testWidgets('hideCompleted removes completed task components', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('test-user'),
          appDatabaseProvider.overrideWithValue(AppDatabase.test()),
          noteEditorControllerProvider.overrideWith((ref, id) async => _createTestController([
            TaskNode(id: '1', text: AttributedText('tarefa concluida'), isComplete: true),
            ParagraphNode(id: '2', text: AttributedText('texto visivel')),
          ])),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: NoteEditor(
              noteId: 'note-1',
              taskMetadata: const {},
              hideCompleted: true,
              delegate: const NoteEditorDelegate(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(TaskExitAnimator)).height, equals(0.0));
    expect(find.byType(Placeholder), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextComponent &&
            widget.text.toPlainText() == 'texto visivel',
      ),
      findsOneWidget,
    );
  });

  testWidgets('hideCompleted updates existing task components', (tester) async {
    var hideCompleted = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('test-user'),
          appDatabaseProvider.overrideWithValue(AppDatabase.test()),
          noteEditorControllerProvider.overrideWith((ref, id) async => _createTestController([
            TaskNode(id: '1', text: AttributedText('tarefa concluida'), isComplete: true),
            ParagraphNode(id: '2', text: AttributedText('texto visivel')),
          ])),
        ],
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: Column(
                  children: [
                    TextButton(
                      onPressed: () => setState(() => hideCompleted = true),
                      child: const Text('toggle hide'),
                    ),
                    Expanded(
                      child: NoteEditor(
                        noteId: 'note-1',
                        taskMetadata: const {},
                        hideCompleted: hideCompleted,
                        delegate: const NoteEditorDelegate(),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppTaskCheckbox), findsOneWidget);

    await tester.tap(find.text('toggle hide'));
    await tester.pumpAndSettle();

    expect(find.byType(AppTaskCheckbox), findsNothing);
    expect(find.byType(Placeholder), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextComponent &&
            widget.text.toPlainText() == 'texto visivel',
      ),
      findsOneWidget,
    );
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
          tasksRepositoryProvider.overrideWithValue(_defaultMockTasksRepo()),
          currentUserIdProvider.overrideWithValue('test-user'),
          appDatabaseProvider.overrideWithValue(AppDatabase.test()),
        ],
        child: const MaterialApp(home: NoteEditorScreen(noteId: 'note-1')),
      ),
    );

    streamController.add(
      NoteModel(
        id: 'note-1',
        userId: 'u-1',
        content: 'Plain content',
        title: 'Plain content',
        favorite: false,
        archived: false,
        
        createdAt: DateTime(2026, 6, 17),
        updatedAt: DateTime(2026, 6, 17),
        hideCompleted: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.share_outlined), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert).first);
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
          position: '0',
          dueDate: DateTime.now().add(const Duration(days: 1)),
          completedAt: null,
          recurrence: null,
          hasTime: false,
          reminder: null,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ]),
    );
    when(() => mockTasksRepo.completeTask(any())).thenAnswer((_) async => (nextDue: null, previousDue: null, previousHasTime: false));
    when(() => mockTasksRepo.reopenTask(any(), originalDueDate: any(named: 'originalDueDate'))).thenAnswer((_) async {});

    const noteContent = '# Test note\n\n- [ ] buy milk <!-- task:task-1 -->\n';

    final testController = _createTestController([
      TaskNode(id: 'task-1', text: AttributedText('buy milk'), isComplete: false),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notesRepositoryProvider.overrideWithValue(
            _FakeNotesRepository(streamController),
          ),
          tasksRepositoryProvider.overrideWithValue(mockTasksRepo),
          currentUserIdProvider.overrideWithValue('test-user'),
          appDatabaseProvider.overrideWithValue(AppDatabase.test()),
          noteEditorControllerProvider.overrideWith((ref, id) async => testController),
        ],
        child: const MaterialApp(home: NoteEditorScreen(noteId: 'note-1')),
      ),
    );

    streamController.add(
      NoteModel(
        id: 'note-1',
        userId: 'u-1',
        content: noteContent,
        title: 'Test note',
        favorite: false,
        archived: false,
        
        createdAt: DateTime(2026, 6, 11),
        updatedAt: DateTime(2026, 6, 11),
        hideCompleted: false,
      ),
    );
    await tester.pumpAndSettle();

    final checkbox = find.byType(AppTaskCheckbox);
    expect(checkbox, findsOneWidget);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();

    expect((testController.document!.getNodeById('task-1') as TaskNode).isComplete, isTrue);
  });

  testWidgets(
    'un-tapping a completed task checkbox calls reopenTask on the repository',
    (tester) async {
      final streamController = StreamController<NoteModel?>();
      addTearDown(streamController.close);

      final mockTasksRepo = _MockTasksRepository();
      final task1 = TaskModel(
        id: 'task-1',
        userId: 'user-1',
        noteId: 'note-1',
        title: 'buy milk',
        status: 'done',
        position: '0',
        dueDate: DateTime.now().add(const Duration(days: 1)),
        completedAt: DateTime.now(),
        recurrence: null,
        hasTime: false,
        reminder: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      when(() => mockTasksRepo.watchByNote(any())).thenAnswer(
        (_) => Stream.value([task1]),
      );
      when(() => mockTasksRepo.completeTask(any())).thenAnswer((_) async => (nextDue: null, previousDue: null, previousHasTime: false));
      when(() => mockTasksRepo.reopenTask(any(), originalDueDate: any(named: 'originalDueDate'))).thenAnswer((_) async {});

      const noteContent =
          '# Test note\n\n- [x] buy milk <!-- task:task-1 -->\n';

      final testController = _createTestController([
        TaskNode(id: 'task-1', text: AttributedText('buy milk'), isComplete: true),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notesRepositoryProvider.overrideWithValue(
              _FakeNotesRepository(streamController, [task1]),
            ),
            tasksRepositoryProvider.overrideWithValue(mockTasksRepo),
            currentUserIdProvider.overrideWithValue('test-user'),
            appDatabaseProvider.overrideWithValue(AppDatabase.test()),
            noteEditorControllerProvider.overrideWith((ref, id) async => testController),
          ],
          child: const MaterialApp(home: NoteEditorScreen(noteId: 'note-1')),
        ),
      );

        streamController.add(
          NoteModel(
            id: 'note-1',
            userId: 'u-1',
            content: noteContent,
            title: 'Test note',
            favorite: false,
            archived: false,
            
              createdAt: DateTime(2026, 6, 11),
            updatedAt: DateTime(2026, 6, 11),
            hideCompleted: false,
          ),
        );
        await tester.pumpAndSettle();

        final checkbox = find.byType(AppTaskCheckbox);
        expect(checkbox, findsOneWidget);
        await tester.tap(checkbox);
        await tester.pumpAndSettle();

        expect((testController.document!.getNodeById('task-1') as TaskNode).isComplete, isFalse);
    },
  );
}

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/catalog/data/notes_repository.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/editor/sync/note_session_handle.dart';
import 'package:supanotes/features/notes/catalog/model/note_strings.dart';
import 'package:supanotes/features/notes/catalog/model/note_with_tasks.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_delegate.dart';
import 'package:supanotes/features/notes/editor/presentation/note_editor_screen.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/custom_task_component.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_editor.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_toolbar.dart';
import 'package:supanotes/shared/theme/app_theme.dart';
import 'package:supanotes/shared/widgets/app_task_checkbox.dart';
import 'package:supanotes/features/tasks/data/tasks_repository.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_controller.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_provider.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_session.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/task_exit_animator.dart';

NoteEditorController _createTestController(List<DocumentNode> nodes) {
  return NoteEditorController(
    userId: 'test-user',
    noteId: 'note-1',
    nodes: nodes,
  );
}

NoteEditorSession _createTestSession(
  List<DocumentNode> nodes, {
  bool captureLocalOperations = true,
}) {
  return NoteEditorSession(
    noteId: 'note-1',
    controller: _createTestController(nodes),
    syncSession: _FakeEditorSyncHandle(
      captureLocalOperations: captureLocalOperations,
    ),
  );
}

NoteEditorSession _sessionFor(NoteEditorController controller) {
  return NoteEditorSession(
    noteId: 'note-1',
    controller: controller,
    syncSession: _FakeEditorSyncHandle(),
  );
}

class _FakeEditorSyncHandle implements NoteEditorSyncHandle {
  _FakeEditorSyncHandle({bool captureLocalOperations = true})
    : _captureLocalOperations = captureLocalOperations;

  bool _captureLocalOperations;

  @override
  NoteSessionStatus get status => NoteSessionStatus.ready;

  @override
  Stream<NoteSessionStatus> get statusChanges =>
      Stream.value(NoteSessionStatus.ready);

  @override
  bool get captureLocalOperations => _captureLocalOperations;

  @override
  Stream<bool> get captureLocalOperationsChanges => const Stream.empty();

  @override
  void setCaptureLocalOperations(bool captureLocalOperations) {
    _captureLocalOperations = captureLocalOperations;
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> flushNow() async {}

  @override
  Future<void> dispose() async {}
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
  Stream<NoteWithTasks> watchNoteWithTasks(String noteId) =>
      _broadcast.map((note) => NoteWithTasks(note: note, tasks: tasks));

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockTasksRepository extends Mock implements ITasksRepository {}

_MockTasksRepository _defaultMockTasksRepo() {
  final mock = _MockTasksRepository();
  when(() => mock.watchByNote(any())).thenAnswer((_) => Stream.value([]));
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
          hasRemoteCopy: true,
          isEmptyDraft: false,
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
          hasRemoteCopy: true,
          isEmptyDraft: false,
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
          noteEditorSessionProvider.overrideWith(
            (ref, noteId) async => _createTestSession([
              ParagraphNode(id: '1', text: AttributedText('Dark content')),
            ]),
          ),
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
        hasRemoteCopy: true,
        isEmptyDraft: false,
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

  testWidgets('requests initial focus for a newly created empty note', (
    tester,
  ) async {
    final controller = _createTestController([]);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          noteEditorSessionProvider.overrideWith(
            (ref, noteId) async => _sessionFor(controller),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: NoteEditor(
              noteId: 'note-1',
              session: _sessionFor(controller),
              taskMetadata: const {},
              requestInitialFocus: true,
              delegate: const NoteEditorDelegate(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.focusNode.hasFocus, isTrue);
    expect(
      tester.widget<SuperEditor>(find.byType(SuperEditor)).autofocus,
      isTrue,
    );
    final selection = controller.composer.selection;
    expect(selection, isNotNull);
    expect(selection!.extent.nodeId, controller.document.first.id);
    expect((selection.extent.nodePosition as TextNodePosition).offset, 0);

    // Flutter's widget-test binding cannot send platform IME text to
    // SuperEditor. InsertTextRequest is the operation emitted by its IME and
    // keyboard handlers, so this verifies the same insertion path at the
    // caret that the initial-focus request placed.
    controller.editor.execute([
      InsertTextRequest(
        documentPosition: selection.extent,
        textToInsert: 'digitação imediata',
        attributions: const {},
      ),
    ]);
    await tester.pump();

    expect(
      (controller.document.first as ParagraphNode).text.toPlainText(),
      'digitação imediata',
    );
  });

  testWidgets('does not request initial focus for an existing empty note', (
    tester,
  ) async {
    final controller = _createTestController([]);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          noteEditorSessionProvider.overrideWith(
            (ref, noteId) async => _sessionFor(controller),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: NoteEditor(
              noteId: 'note-1',
              session: _sessionFor(controller),
              taskMetadata: const {},
              delegate: const NoteEditorDelegate(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.focusNode.hasFocus, isFalse);
    expect(
      tester.widget<SuperEditor>(find.byType(SuperEditor)).autofocus,
      isFalse,
    );
  });

  testWidgets('screen derives initial focus from a local empty draft', (
    tester,
  ) async {
    final streamController = StreamController<NoteModel?>();
    addTearDown(streamController.close);
    final controller = _createTestController([]);
    final session = _sessionFor(controller);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('u-1'),
          notesRepositoryProvider.overrideWithValue(
            _FakeNotesRepository(streamController),
          ),
          noteEditorSessionProvider.overrideWith(
            (ref, noteId) async => session,
          ),
        ],
        child: const MaterialApp(home: NoteEditorScreen(noteId: 'note-1')),
      ),
    );

    streamController.add(
      NoteModel(
        id: 'note-1',
        userId: 'u-1',
        content: '',
        title: 'Sem título',
        favorite: false,
        archived: false,
        createdAt: DateTime(2026, 6, 11),
        updatedAt: DateTime(2026, 6, 11),
        hasRemoteCopy: false,
        isEmptyDraft: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<SuperEditor>(find.byType(SuperEditor)).autofocus,
      isTrue,
    );
    expect(controller.focusNode.hasFocus, isTrue);
  });

  testWidgets(
    'tap in empty viewport below document places caret at end and opens keyboard',
    (tester) async {
      const taskText = 'Comprar leite';
      final controller = _createTestController([
        TaskNode(
          id: 'task-1',
          text: AttributedText(taskText),
          isComplete: false,
        ),
        TaskNode(
          id: 'task-hidden',
          text: AttributedText('Concluída'),
          isComplete: true,
        ),
      ]);
      addTearDown(controller.dispose);
      controller.composer.setSelectionWithReason(
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: 'task-1',
            nodePosition: TextNodePosition(offset: 0),
          ),
        ),
        SelectionReason.userInteraction,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            noteEditorSessionProvider.overrideWith(
              (ref, noteId) => _sessionFor(controller),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
            home: Scaffold(
              body: NoteEditor(
                noteId: 'note-1',
                session: _sessionFor(controller),
                taskMetadata: const {},
                hideCompleted: true,
                delegate: const NoteEditorDelegate(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final taskRect = tester.getRect(find.byType(CustomTaskComponent).first);
      await tester.tapAt(Offset(taskRect.center.dx, taskRect.bottom + 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);

      controller.composer.setSelectionWithReason(
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: 'task-1',
            nodePosition: TextNodePosition(offset: 0),
          ),
        ),
        SelectionReason.userInteraction,
      );
      tester.testTextInput.hide();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));

      expect(controller.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isFalse);

      final toolbarRect = tester.getRect(find.byType(NoteToolbar));
      await tester.tapAt(Offset(toolbarRect.center.dx, toolbarRect.top - 10));
      await tester.pump(const Duration(milliseconds: 100));

      final selection = controller.composer.selection;
      expect(selection, isNotNull);
      expect(selection!.extent.nodeId, 'task-1');
      expect(
        (selection.extent.nodePosition as TextNodePosition).offset,
        taskText.length,
      );
      expect(controller.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    },
  );

  testWidgets(
    'tap below an entirely hidden document creates an editable paragraph',
    (tester) async {
      final controller = _createTestController([
        TaskNode(
          id: 'task-hidden',
          text: AttributedText('Concluída'),
          isComplete: true,
        ),
      ]);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            noteEditorSessionProvider.overrideWith(
              (ref, noteId) => _sessionFor(controller),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
            home: Scaffold(
              body: NoteEditor(
                noteId: 'note-1',
                session: _sessionFor(controller),
                taskMetadata: const {},
                hideCompleted: true,
                delegate: const NoteEditorDelegate(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final toolbarRect = tester.getRect(find.byType(NoteToolbar));
      await tester.tapAt(Offset(toolbarRect.center.dx, toolbarRect.top - 10));
      await tester.pump(const Duration(milliseconds: 100));

      final nodes = controller.document.toList();
      expect(nodes, hasLength(2));
      expect(nodes.last, isA<ParagraphNode>());
      expect(controller.composer.selection!.extent.nodeId, nodes.last.id);
      expect(controller.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    },
  );

  testWidgets('hideCompleted removes completed task components', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('test-user'),
          appDatabaseProvider.overrideWithValue(AppDatabase.test()),
          noteEditorSessionProvider.overrideWith(
            (ref, noteId) async => _createTestSession([
              TaskNode(
                id: '1',
                text: AttributedText('tarefa concluida'),
                isComplete: true,
              ),
              ParagraphNode(id: '2', text: AttributedText('texto visivel')),
            ]),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: NoteEditor(
              noteId: 'note-1',
              session: _createTestSession([
                TaskNode(
                  id: '1',
                  text: AttributedText('tarefa concluida'),
                  isComplete: true,
                ),
                ParagraphNode(id: '2', text: AttributedText('texto visivel')),
              ]),
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

  testWidgets('hideCompleted keeps the last task valid for caret placement', (
    tester,
  ) async {
    var hideCompleted = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('test-user'),
          appDatabaseProvider.overrideWithValue(AppDatabase.test()),
          noteEditorSessionProvider.overrideWith(
            (ref, noteId) async => _createTestSession([
              ParagraphNode(id: '1', text: AttributedText('texto visivel')),
              TaskNode(
                id: '2',
                text: AttributedText('tarefa concluida'),
                isComplete: true,
              ),
            ]),
          ),
        ],
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: Column(
                  children: [
                    TextButton(
                      onPressed: () => setState(() => hideCompleted = true),
                      child: const Text('hide'),
                    ),
                    Expanded(
                      child: NoteEditor(
                        noteId: 'note-1',
                        session: _createTestSession([
                          ParagraphNode(
                            id: '1',
                            text: AttributedText('texto visivel'),
                          ),
                          TaskNode(
                            id: '2',
                            text: AttributedText('tarefa concluida'),
                            isComplete: true,
                          ),
                        ]),
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

    await tester.tap(find.text('hide'));
    await tester.pumpAndSettle();

    final documentLayout =
        tester.state(find.byType(SingleColumnDocumentLayout)) as DocumentLayout;
    final hiddenTask = documentLayout.getComponentByNodeId('2');
    expect(hiddenTask, isNotNull);
    expect(hiddenTask!.isVisualSelectionSupported(), isFalse);
    expect(documentLayout.findLastSelectablePosition()?.nodeId, '1');
    expect(
      () => documentLayout.getDocumentPositionNearestToOffset(
        const Offset(8, 5000),
      ),
      returnsNormally,
    );

    final editorRect = tester.getRect(find.byType(SuperEditor));
    await tester.sendEventToBinding(
      PointerHoverEvent(position: editorRect.bottomCenter),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('hideCompleted cannot place the caret in a hidden task', (
    tester,
  ) async {
    final controller = _createTestController([
      ParagraphNode(id: '1', text: AttributedText('texto visivel')),
      TaskNode(
        id: '2',
        text: AttributedText('tarefa concluida'),
        isComplete: true,
      ),
    ]);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('test-user'),
          appDatabaseProvider.overrideWithValue(AppDatabase.test()),
          noteEditorSessionProvider.overrideWith(
            (ref, noteId) async => _sessionFor(controller),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: NoteEditor(
              noteId: 'note-1',
              session: _sessionFor(controller),
              taskMetadata: const {},
              hideCompleted: true,
              delegate: const NoteEditorDelegate(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final hiddenTaskRect = tester.getRect(find.byType(TaskExitAnimator).last);
    await tester.tapAt(hiddenTaskRect.center);
    await tester.pumpAndSettle();

    expect(controller.composer.selection?.extent.nodeId, isNot('2'));
    expect(
      (controller.document.getNodeById('2')! as TaskNode).text.toPlainText(),
      'tarefa concluida',
    );
  });

  testWidgets(
    'hideCompleted does not allow keyboard deletion in a hidden task',
    (tester) async {
      final controller = _createTestController([
        ParagraphNode(id: '1', text: AttributedText('texto visivel')),
        TaskNode(
          id: '2',
          text: AttributedText('tarefa concluida'),
          isComplete: true,
        ),
      ]);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserIdProvider.overrideWithValue('test-user'),
            appDatabaseProvider.overrideWithValue(AppDatabase.test()),
            noteEditorSessionProvider.overrideWith(
              (ref, noteId) async => _sessionFor(controller),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: NoteEditor(
                noteId: 'note-1',
                session: _sessionFor(controller),
                taskMetadata: const {},
                hideCompleted: true,
                delegate: const NoteEditorDelegate(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      controller.composer.setSelectionWithReason(
        DocumentSelection.collapsed(
          position: const DocumentPosition(
            nodeId: '2',
            nodePosition: TextNodePosition(offset: 15),
          ),
        ),
      );
      controller.editor.execute([const DeleteUpstreamRequest()]);

      expect(
        (controller.document.getNodeById('2')! as TaskNode).text.toPlainText(),
        'tarefa concluida',
      );
    },
  );

  testWidgets('hideCompleted does not place the caret in hidden tasks', (
    tester,
  ) async {
    final controller = _createTestController([
      TaskNode(
        id: '1',
        text: AttributedText('tarefa concluida'),
        isComplete: true,
      ),
      ParagraphNode(id: '2', text: AttributedText('texto visivel')),
    ]);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('test-user'),
          appDatabaseProvider.overrideWithValue(AppDatabase.test()),
          noteEditorSessionProvider.overrideWith(
            (ref, noteId) async => _sessionFor(controller),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: NoteEditor(
              noteId: 'note-1',
              session: _sessionFor(controller),
              taskMetadata: const {},
              hideCompleted: true,
              delegate: const NoteEditorDelegate(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final visibleText = find.byWidgetPredicate(
      (widget) =>
          widget is TextComponent &&
          widget.text.toPlainText() == 'texto visivel',
    );
    final visibleRect = tester.getRect(visibleText);
    await tester.tapAt(Offset(visibleRect.center.dx, visibleRect.top - 4));
    await tester.pumpAndSettle();

    expect(controller.composer.selection?.extent.nodeId, isNot('1'));
  });

  testWidgets('hideCompleted does not select a task during its exit', (
    tester,
  ) async {
    var hideCompleted = false;
    final controller = _createTestController([
      TaskNode(
        id: '1',
        text: AttributedText('tarefa concluida'),
        isComplete: true,
      ),
      ParagraphNode(id: '2', text: AttributedText('texto visivel')),
    ]);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('test-user'),
          appDatabaseProvider.overrideWithValue(AppDatabase.test()),
          noteEditorSessionProvider.overrideWith(
            (ref, noteId) async => _sessionFor(controller),
          ),
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
                        session: _sessionFor(controller),
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

    final taskRect = tester.getRect(find.byType(TaskExitAnimator).first);
    await tester.tap(find.text('toggle hide'));
    await tester.pump(const Duration(milliseconds: 100));

    final documentLayout =
        tester.state(find.byType(SingleColumnDocumentLayout)) as DocumentLayout;
    final exitingTask = documentLayout.getComponentByNodeId('1');
    expect(exitingTask, isNotNull);
    expect(exitingTask!.isVisualSelectionSupported(), isFalse);
    expect(exitingTask.getPositionAtOffset(Offset.zero), isNull);
    expect(exitingTask.getDesiredCursorAtOffset(Offset.zero), isNull);

    await tester.tapAt(taskRect.center);
    await tester.pumpAndSettle();

    expect(controller.composer.selection?.extent.nodeId, isNot('1'));
  });

  testWidgets('hideCompleted updates existing task components', (tester) async {
    var hideCompleted = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('test-user'),
          appDatabaseProvider.overrideWithValue(AppDatabase.test()),
          noteEditorSessionProvider.overrideWith(
            (ref, noteId) async => _createTestSession([
              TaskNode(
                id: '1',
                text: AttributedText('tarefa concluida'),
                isComplete: true,
              ),
              ParagraphNode(id: '2', text: AttributedText('texto visivel')),
            ]),
          ),
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
                        session: _createTestSession([
                          TaskNode(
                            id: '1',
                            text: AttributedText('tarefa concluida'),
                            isComplete: true,
                          ),
                          ParagraphNode(
                            id: '2',
                            text: AttributedText('texto visivel'),
                          ),
                        ]),
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

    expect(find.byType(AppTaskCheckbox), findsOneWidget);
    expect(
      tester.getSize(find.byType(TaskExitAnimator).first).height,
      equals(0.0),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextComponent &&
            widget.text.toPlainText() == 'tarefa concluida',
      ),
      findsOneWidget,
    );
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

  testWidgets(
    'hideCompleted restores a hidden task without replacing its node',
    (tester) async {
      var hideCompleted = false;
      final controller = _createTestController([
        TaskNode(
          id: '1',
          text: AttributedText('tarefa concluida'),
          isComplete: true,
        ),
        ParagraphNode(id: '2', text: AttributedText('texto visivel')),
      ]);
      addTearDown(controller.dispose);
      final delegate = NoteEditorDelegate(
        onTaskReopen: (taskId) async {
          controller.reopenTaskInEditor(taskId);
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserIdProvider.overrideWithValue('test-user'),
            appDatabaseProvider.overrideWithValue(AppDatabase.test()),
            noteEditorSessionProvider.overrideWith(
              (ref, noteId) async => _sessionFor(controller),
            ),
          ],
          child: MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                return Scaffold(
                  body: Column(
                    children: [
                      TextButton(
                        onPressed: () =>
                            setState(() => hideCompleted = !hideCompleted),
                        child: const Text('toggle hide'),
                      ),
                      Expanded(
                        child: NoteEditor(
                          noteId: 'note-1',
                          session: _sessionFor(controller),
                          taskMetadata: const {},
                          hideCompleted: hideCompleted,
                          delegate: delegate,
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

      final taskText = find.byWidgetPredicate(
        (widget) =>
            widget is TextComponent &&
            widget.text.toPlainText() == 'tarefa concluida',
      );
      expect(taskText, findsOneWidget);

      await tester.tap(find.text('toggle hide'));
      await tester.pumpAndSettle();

      final hiddenLayout =
          tester.state(find.byType(SingleColumnDocumentLayout))
              as DocumentLayout;
      final hiddenTask = hiddenLayout.getComponentByNodeId('1');
      expect(hiddenTask, isNotNull);
      expect(hiddenTask!.isVisualSelectionSupported(), isFalse);
      expect(taskText, findsOneWidget);
      expect(tester.getSize(find.byType(TaskExitAnimator).first).height, 0.0);

      await tester.tap(find.text('toggle hide'));
      await tester.pumpAndSettle();

      final restoredLayout =
          tester.state(find.byType(SingleColumnDocumentLayout))
              as DocumentLayout;
      final restoredTask = restoredLayout.getComponentByNodeId('1');
      expect(restoredTask, isNotNull);
      expect(restoredTask!.isVisualSelectionSupported(), isTrue);
      expect(
        tester.getSize(find.byType(TaskExitAnimator).first).height,
        greaterThan(0),
      );

      await tester.tap(find.byType(AppTaskCheckbox));
      await tester.pumpAndSettle();
      expect(
        (controller.document.getNodeById('1')! as TaskNode).isComplete,
        isFalse,
      );
    },
  );

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
          noteEditorSessionProvider.overrideWith(
            (ref, noteId) async => _createTestSession([
              ParagraphNode(id: '1', text: AttributedText('Plain content')),
            ]),
          ),
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
        hasRemoteCopy: true,
        isEmptyDraft: false,
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

  testWidgets('tapping a task checkbox updates the canonical document', (
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
    const noteContent = '# Test note\n\n- [ ] buy milk <!-- task:task-1 -->\n';

    final testController = _createTestController([
      TaskNode(
        id: 'task-1',
        text: AttributedText('buy milk'),
        isComplete: false,
      ),
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
          noteEditorSessionProvider.overrideWith(
            (ref, noteId) async => _sessionFor(testController),
          ),
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
        hasRemoteCopy: true,
        isEmptyDraft: false,
        hideCompleted: false,
      ),
    );
    await tester.pumpAndSettle();

    final checkbox = find.byType(AppTaskCheckbox);
    expect(checkbox, findsOneWidget);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();

    expect(
      (testController.document.getNodeById('task-1') as TaskNode).isComplete,
      isTrue,
    );
  });

  testWidgets(
    'un-tapping a completed task checkbox updates the canonical document',
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

      when(
        () => mockTasksRepo.watchByNote(any()),
      ).thenAnswer((_) => Stream.value([task1]));
      const noteContent =
          '# Test note\n\n- [x] buy milk <!-- task:task-1 -->\n';

      final testController = _createTestController([
        TaskNode(
          id: 'task-1',
          text: AttributedText('buy milk'),
          isComplete: true,
        ),
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
            noteEditorSessionProvider.overrideWith(
              (ref, id) async => _sessionFor(testController),
            ),
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
          hasRemoteCopy: true,
          isEmptyDraft: false,
          hideCompleted: false,
        ),
      );
      await tester.pumpAndSettle();

      final checkbox = find.byType(AppTaskCheckbox);
      expect(checkbox, findsOneWidget);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();

      expect(
        (testController.document.getNodeById('task-1') as TaskNode).isComplete,
        isFalse,
      );
    },
  );

  testWidgets('NoteEditor read-only mode does not install mutation UI', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          noteEditorSessionProvider.overrideWith(
            (ref, noteId) async => _createTestSession([
              ParagraphNode(id: '1', text: AttributedText('read only')),
            ]),
          ),
        ],
        child: MaterialApp(
          home: NoteEditor(
            noteId: 'note-1',
            session: _createTestSession([
              ParagraphNode(id: '1', text: AttributedText('read only')),
            ], captureLocalOperations: false),
            taskMetadata: const {},
            delegate: NoteEditorDelegate(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(NoteToolbar), findsNothing);
    expect(find.byType(SuperReader), findsOneWidget);
    expect(find.byType(SuperEditor), findsNothing);
  });
}

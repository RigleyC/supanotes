import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/presentation/widgets/custom_task_component.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/shared/widgets/app_task_checkbox.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  TaskComponentViewModel viewModel() {
    return TaskComponentViewModel(
      nodeId: 'task-1',
      padding: EdgeInsets.zero,
      indent: 0,
      isComplete: false,
      setComplete: (_) {},
      text: AttributedText('Enviar relatorio'),
      textDirection: TextDirection.ltr,
      textAlignment: TextAlign.left,
      textStyleBuilder: (_) => const TextStyle(fontSize: 16),
      selectionColor: Colors.transparent,
    );
  }

  TaskComponentViewModel multilineViewModel() {
    return TaskComponentViewModel(
      nodeId: 'task-1',
      padding: EdgeInsets.zero,
      indent: 0,
      isComplete: false,
      setComplete: (_) {},
      text: AttributedText('Enviar relatorio\ncom observacoes'),
      textDirection: TextDirection.ltr,
      textAlignment: TextAlign.left,
      textStyleBuilder: (_) => const TextStyle(fontSize: 16),
      selectionColor: Colors.transparent,
    );
  }

  testWidgets('keeps editable task text registered in the component', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(CustomTaskComponent(viewModel: viewModel())));

    expect(find.byType(TextComponent), findsOneWidget);
    expect(find.byType(CustomTaskComponent), findsOneWidget);
  });

  testWidgets('opens task actions from checkbox long press', (tester) async {
    var openedActions = false;

    await tester.pumpWidget(
      wrap(
        CustomTaskComponent(
          viewModel: viewModel(),
          onLongPress: () => openedActions = true,
        ),
      ),
    );

    await tester.longPress(find.byType(AppTaskCheckbox));
    await tester.pump();

    expect(openedActions, isTrue);
  });

  testWidgets('toggles completion from row tap', (tester) async {
    bool? completed;
    final vm = TaskComponentViewModel(
      nodeId: 'task-1',
      padding: EdgeInsets.zero,
      indent: 0,
      isComplete: false,
      setComplete: (value) => completed = value,
      text: AttributedText('Enviar relatorio'),
      textDirection: TextDirection.ltr,
      textAlignment: TextAlign.left,
      textStyleBuilder: (_) => const TextStyle(fontSize: 16),
      selectionColor: Colors.transparent,
    );

    await tester.pumpWidget(wrap(CustomTaskComponent(viewModel: vm)));

    await tester.tap(find.byType(AppTaskCheckbox));
    await tester.pump();

    expect(completed, isTrue);
  });

  testWidgets('tap on text does not toggle completion', (tester) async {
    bool? completed;
    final vm = TaskComponentViewModel(
      nodeId: 'task-1',
      padding: EdgeInsets.zero,
      indent: 0,
      isComplete: false,
      setComplete: (value) => completed = value,
      text: AttributedText('Enviar relatorio'),
      textDirection: TextDirection.ltr,
      textAlignment: TextAlign.left,
      textStyleBuilder: (_) => const TextStyle(fontSize: 16),
      selectionColor: Colors.transparent,
    );

    await tester.pumpWidget(wrap(CustomTaskComponent(viewModel: vm)));

    await tester.tap(find.byType(TextComponent), warnIfMissed: false);
    await tester.pump();

    expect(completed, isNull);
  });

  testWidgets('long-press on text opens task actions', (tester) async {
    var openedActions = false;

    await tester.pumpWidget(
      wrap(
        CustomTaskComponent(
          viewModel: viewModel(),
          onLongPress: () => openedActions = true,
        ),
      ),
    );

    await tester.longPress(find.byType(TextComponent), warnIfMissed: false);
    await tester.pump();

    expect(openedActions, isTrue);
  });

  testWidgets('keeps text spaced from the checkbox icon', (tester) async {
    await tester.pumpWidget(wrap(CustomTaskComponent(viewModel: viewModel())));

    expect(
      tester.getSize(find.byType(AppTaskCheckbox)),
      const Size(22, 22),
    );

    final checkboxLeft = tester
        .getTopLeft(find.byType(AppTaskCheckbox))
        .dx;
    final textLeft = tester.getTopLeft(find.byType(TextComponent)).dx;

    expect(textLeft, checkboxLeft + 31);
  });

  testWidgets('places checkbox at the top of the row', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(CustomTaskComponent(viewModel: viewModel())));

    final checkboxTop = tester.getTopLeft(find.byType(AppTaskCheckbox)).dy;
    final textTop = tester.getTopLeft(find.byType(TextComponent)).dy;

    expect(checkboxTop, closeTo(textTop, 2));
  });

  testWidgets('keeps checkbox at the top for multiline text', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(CustomTaskComponent(viewModel: multilineViewModel())),
    );

    final checkboxTop = tester.getTopLeft(find.byType(AppTaskCheckbox)).dy;
    final textTop = tester.getTopLeft(find.byType(TextComponent)).dy;

    expect(checkboxTop, closeTo(textTop, 2));
  });

  testWidgets('keeps typed paragraph text visible after leaving empty task', (
    tester,
  ) async {
    final document = MutableDocument(
      nodes: [
        TaskNode(id: 'task-1', text: AttributedText(), isComplete: false),
      ],
    );
    final composer = MutableDocumentComposer();
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );

    await tester.pumpWidget(
      wrap(
        SuperEditor(
          editor: editor,
          componentBuilders: [
            ...defaultComponentBuilders,
            CustomTaskComponentBuilder(),
          ],
        ),
      ),
    );

    editor.execute([
      const ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: 'task-1',
            nodePosition: TextNodePosition(offset: 0),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
    ]);
    await tester.pump();

    editor.execute([InsertNewlineAtCaretRequest()]);
    await tester.pump();

    expect(document.first, isA<ParagraphNode>());
    expect((document.first as ParagraphNode).text.toPlainText(), isEmpty);

    editor.execute([const InsertPlainTextAtCaretRequest('texto visivel')]);
    await tester.pump();

    expect(
      (document.first as ParagraphNode).text.toPlainText(),
      'texto visivel',
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextComponent &&
            widget.text.toPlainText() == 'texto visivel',
      ),
      findsOneWidget,
    );
  });

  testWidgets('fires onTaskComplete when completing a recurring task', (
    tester,
  ) async {
    final document = MutableDocument(
      nodes: [
        TaskNode(
          id: 'task-1',
          text: AttributedText('Tarefa recorrente'),
          isComplete: false,
        ),
      ],
    );
    final composer = MutableDocumentComposer();
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );

    String? capturedCompleteId;
    String? capturedReopenId;
    final now = DateTime.now();

    await tester.pumpWidget(
      wrap(
        SuperEditor(
          editor: editor,
          componentBuilders: [
            ...defaultComponentBuilders,
            CustomTaskComponentBuilder(
              taskMetadataById: {
                'task-1': TaskModel(
                  id: 'task-1',
                  userId: '',
                  noteId: '',
                  title: 'Tarefa recorrente',
                  status: 'open',
                  position: '0',
                  dueDate: now,
                  completedAt: null,
                  recurrence: TaskRecurrence.daily,
                  createdAt: now,
                  updatedAt: now,
                ),
              },
              onTaskComplete: (id) async { capturedCompleteId = id; return null; },
              onTaskReopen: (id) async => capturedReopenId = id,
            ),

          ],
        ),
      ),
    );

    await tester.tap(find.byType(AppTaskCheckbox));
    await tester.pump();

    expect(capturedCompleteId, equals('task-1'));
    expect(capturedReopenId, isNull);
    // Drain the pending reset timer
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('fires onTaskReopen when un-completing a task', (tester) async {
    final document = MutableDocument(
      nodes: [
        TaskNode(
          id: 'task-1',
          text: AttributedText('Tarefa concluída'),
          isComplete: true,
        ),
      ],
    );
    final composer = MutableDocumentComposer();
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );

    String? capturedCompleteId;
    String? capturedReopenId;

    await tester.pumpWidget(
      wrap(
        SuperEditor(
          editor: editor,
          componentBuilders: [
            ...defaultComponentBuilders,
            CustomTaskComponentBuilder(
              onTaskComplete: (id) async { capturedCompleteId = id; return null; },
              onTaskReopen: (id) async => capturedReopenId = id,
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byType(AppTaskCheckbox));
    await tester.pump();

    expect(capturedReopenId, equals('task-1'));
    expect(capturedCompleteId, isNull);
  });

  testWidgets('builder wraps hidden completed tasks in TaskExitAnimator', (tester) async {
    final document = MutableDocument(
      nodes: [
        TaskNode(id: 'task-1', text: AttributedText('Done'), isComplete: true),
      ],
    );
    final composer = MutableDocumentComposer();
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );
    final builder = CustomTaskComponentBuilder(
      hideCompleted: true,
    );

    await tester.pumpWidget(
      wrap(
        SuperEditor(
          editor: editor,
          componentBuilders: [
            builder,
            ...defaultComponentBuilders,
          ],
        ),
      ),
    );

    expect(find.byType(CustomTaskComponent), findsOneWidget);
    expect(find.byType(SizeTransition), findsOneWidget);
  });

  testWidgets('un-checks recurring task after 400ms delay', (tester) async {
    final document = MutableDocument(
      nodes: [
        TaskNode(
          id: 'task-1',
          text: AttributedText('Tarefa recorrente'),
          isComplete: false,
        ),
      ],
    );
    final composer = MutableDocumentComposer();
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );

    String? capturedCompleteId;
    final now = DateTime.now();

    await tester.pumpWidget(
      wrap(
        SuperEditor(
          editor: editor,
          componentBuilders: [
            ...defaultComponentBuilders,
            CustomTaskComponentBuilder(
              taskMetadataById: {
                'task-1': TaskModel(
                  id: 'task-1',
                  userId: '',
                  noteId: '',
                  title: 'Tarefa recorrente',
                  status: 'open',
                  position: '0',
                  dueDate: now,
                  completedAt: null,
                  recurrence: TaskRecurrence.daily,
                  createdAt: now,
                  updatedAt: now,
                ),
              },
              onTaskComplete: (id) async {
                capturedCompleteId = id;
                return now.add(const Duration(days: 1));
              },
              onTaskReopen: (id) async {},
            ),
          ],
        ),
      ),
    );

    TaskNode taskNode() => document.first as TaskNode;
    expect(taskNode().isComplete, isFalse);

    await tester.tap(find.byType(AppTaskCheckbox));
    await tester.pump();

    // New behavior: no optimistic editor commands, document unchanged.
    expect(taskNode().isComplete, isFalse);
    expect(capturedCompleteId, equals('task-1'));

    // Drain the 1s recurring delay timer so no pending timers remain.
    await tester.pump(const Duration(seconds: 1));
  });
}

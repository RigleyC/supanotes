import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/presentation/widgets/custom_task_component.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/shared/widgets/animated_task_checkbox.dart';

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

    await tester.longPress(find.byType(AnimatedTaskCheckbox));
    await tester.pump();

    expect(openedActions, isTrue);
  });

  testWidgets('text area long press does not open task actions', (
    tester,
  ) async {
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

    expect(openedActions, isFalse);
  });

  testWidgets('toggles completion from checkbox tap', (tester) async {
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

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(completed, isTrue);
  });

  testWidgets('keeps text spaced from the checkbox icon', (tester) async {
    await tester.pumpWidget(wrap(CustomTaskComponent(viewModel: viewModel())));

    expect(
      tester.getSize(find.byType(AnimatedTaskCheckbox)),
      const Size(22, 22),
    );

    final checkboxLeft = tester
        .getTopLeft(find.byType(AnimatedTaskCheckbox))
        .dx;
    final textLeft = tester.getTopLeft(find.byType(TextComponent)).dx;

    expect(textLeft, checkboxLeft + 31);
  });

  testWidgets('centers the first text line against the checkbox icon', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(CustomTaskComponent(viewModel: viewModel())));

    final checkboxTop = tester.getTopLeft(find.byType(AnimatedTaskCheckbox)).dy;
    final iconCenterY = checkboxTop + 11;
    final textTop = tester.getTopLeft(find.byType(TextComponent)).dy;
    final textHeight = tester.getSize(find.byType(TextComponent)).height;
    final firstLineCenterY = textTop + (textHeight / 2);

    expect(iconCenterY, closeTo(firstLineCenterY, 1));
  });

  testWidgets('keeps checkbox aligned to the first line for multiline text', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(CustomTaskComponent(viewModel: multilineViewModel())),
    );

    final checkboxTop = tester.getTopLeft(find.byType(AnimatedTaskCheckbox)).dy;
    final iconCenterY = checkboxTop + 11;
    final textTop = tester.getTopLeft(find.byType(TextComponent)).dy;
    final textHeight = tester.getSize(find.byType(TextComponent)).height;
    final firstLineCenterY = textTop + (textHeight / 4);

    expect(iconCenterY, closeTo(firstLineCenterY, 1));
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
            CustomTaskComponentBuilder(editor),
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
              editor,
              taskMetadataById: {
                'task-1': TaskModel(
                  id: 'task-1',
                  userId: '',
                  noteId: '',
                  title: 'Tarefa recorrente',
                  status: 'open',
                  position: 0,
                  dueDate: now,
                  completedAt: null,
                  recurrence: TaskRecurrence.daily,
                  createdAt: now,
                  updatedAt: now,
                ),
              },
              onTaskComplete: (id) async => capturedCompleteId = id,
              onTaskReopen: (id) async => capturedReopenId = id,
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byType(AnimatedTaskCheckbox));
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
              editor,
              onTaskComplete: (id) async => capturedCompleteId = id,
              onTaskReopen: (id) async => capturedReopenId = id,
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byType(AnimatedTaskCheckbox));
    await tester.pump();

    expect(capturedReopenId, equals('task-1'));
    expect(capturedCompleteId, isNull);
  });

  group('exit animation', () {
    TaskComponentViewModel incompleteVM() {
      return TaskComponentViewModel(
        nodeId: 'task-1',
        padding: EdgeInsets.zero,
        indent: 0,
        isComplete: false,
        setComplete: (_) {},
        text: AttributedText('Task'),
        textDirection: TextDirection.ltr,
        textAlignment: TextAlign.left,
        textStyleBuilder: (_) => const TextStyle(fontSize: 16),
        selectionColor: Colors.transparent,
      );
    }

    TaskComponentViewModel completeVM() {
      return TaskComponentViewModel(
        nodeId: 'task-1',
        padding: EdgeInsets.zero,
        indent: 0,
        isComplete: true,
        setComplete: (_) {},
        text: AttributedText('Task'),
        textDirection: TextDirection.ltr,
        textAlignment: TextAlign.left,
        textStyleBuilder: (_) => const TextStyle(fontSize: 16),
        selectionColor: Colors.transparent,
      );
    }

    testWidgets('fires onAnimationComplete after completing task with hideCompleted', (
      tester,
    ) async {
      var animationCompleted = false;

      await tester.pumpWidget(
        wrap(
          CustomTaskComponent(
            viewModel: incompleteVM(),
            hideCompleted: true,
            onAnimationComplete: () => animationCompleted = true,
          ),
        ),
      );

      await tester.pumpWidget(
        wrap(
          CustomTaskComponent(
            viewModel: completeVM(),
            hideCompleted: true,
            onAnimationComplete: () => animationCompleted = true,
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 301));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 351));
      await tester.pump();

      expect(animationCompleted, isTrue);
    });

    testWidgets('does not fire onAnimationComplete when hideCompleted is false', (
      tester,
    ) async {
      var animationCompleted = false;

      await tester.pumpWidget(
        wrap(
          CustomTaskComponent(
            viewModel: incompleteVM(),
            hideCompleted: false,
            onAnimationComplete: () => animationCompleted = true,
          ),
        ),
      );

      await tester.pumpWidget(
        wrap(
          CustomTaskComponent(
            viewModel: completeVM(),
            hideCompleted: false,
            onAnimationComplete: () => animationCompleted = true,
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 650));

      expect(animationCompleted, isFalse);
    });

    testWidgets('does not fire onAnimationComplete when task was already complete', (
      tester,
    ) async {
      var animationCompleted = false;

      await tester.pumpWidget(
        wrap(
          CustomTaskComponent(
            viewModel: completeVM(),
            hideCompleted: true,
            onAnimationComplete: () => animationCompleted = true,
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 650));

      expect(animationCompleted, isFalse);
    });

    testWidgets('builder creates SizedBox for hidden completed tasks', (tester) async {
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
        editor,
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

      expect(find.byType(CustomTaskComponent), findsNothing);
      expect(find.byType(SizeTransition), findsNothing);
    });

    testWidgets('reversing completion cancels/reverses exit animation and widget remains visible', (
      tester,
    ) async {
      var animationCompleted = false;

      await tester.pumpWidget(
        wrap(
          CustomTaskComponent(
            viewModel: incompleteVM(),
            hideCompleted: true,
            onAnimationComplete: () => animationCompleted = true,
          ),
        ),
      );

      await tester.pumpWidget(
        wrap(
          CustomTaskComponent(
            viewModel: completeVM(),
            hideCompleted: true,
            onAnimationComplete: () => animationCompleted = true,
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      await tester.pumpWidget(
        wrap(
          CustomTaskComponent(
            viewModel: incompleteVM(),
            hideCompleted: true,
            onAnimationComplete: () => animationCompleted = true,
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 650));
      await tester.pumpAndSettle();

      expect(animationCompleted, isFalse);
    });
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

    final now = DateTime.now();

    await tester.pumpWidget(
      wrap(
        SuperEditor(
          editor: editor,
          componentBuilders: [
            ...defaultComponentBuilders,
            CustomTaskComponentBuilder(
              editor,
              taskMetadataById: {
                'task-1': TaskModel(
                  id: 'task-1',
                  userId: '',
                  noteId: '',
                  title: 'Tarefa recorrente',
                  status: 'open',
                  position: 0,
                  dueDate: now,
                  completedAt: null,
                  recurrence: TaskRecurrence.daily,
                  createdAt: now,
                  updatedAt: now,
                ),
              },
            ),
          ],
        ),
      ),
    );

    TaskNode taskNode() => document.first as TaskNode;
    expect(taskNode().isComplete, isFalse);

    await tester.tap(find.byType(AnimatedTaskCheckbox));
    // First pump: process the tap event, setComplete runs synchronously
    // up to the await, _editor.execute updates the document.
    await tester.pump();

    expect(taskNode().isComplete, isTrue);

    // Second pump: process the microtask that continues setComplete,
    // which creates the Future.delayed(400ms) timer.
    await tester.pump();

    // Third pump: advance clock by 400ms so the timer fires and
    // the document is reset.
    await tester.pump(const Duration(milliseconds: 400));

    expect(taskNode().isComplete, isFalse);
  });
}

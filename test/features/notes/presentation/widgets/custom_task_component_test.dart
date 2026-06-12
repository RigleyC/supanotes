import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/presentation/widgets/custom_task_component.dart';

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

  testWidgets('keeps editable task text registered in the component', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(CustomTaskComponent(viewModel: viewModel())));

    expect(find.byType(TextComponent), findsOneWidget);
    expect(find.byType(CustomTaskComponent), findsOneWidget);
  });

  testWidgets('opens task actions from text area long press', (tester) async {
    var openedActions = false;

    await tester.pumpWidget(
      wrap(
        CustomTaskComponent(
          viewModel: viewModel(),
          onLongPress: () => openedActions = true,
        ),
      ),
    );

    await tester.longPress(
      find
          .ancestor(
            of: find.byType(TextComponent),
            matching: find.byType(Listener),
          )
          .first,
    );
    await tester.pump();

    expect(openedActions, isTrue);
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

    await tester.longPress(find.byType(InkWell));
    await tester.pump();

    expect(openedActions, isTrue);
  });

  testWidgets('toggles completion from checkbox tap', (tester) async {
    bool? completed;
    final viewModel = TaskComponentViewModel(
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

    await tester.pumpWidget(wrap(CustomTaskComponent(viewModel: viewModel)));

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(completed, isTrue);
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
}

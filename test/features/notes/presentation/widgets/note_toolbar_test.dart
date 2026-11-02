import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_codec.dart';
import 'package:supanotes/features/notes/editor/document/note_blocks.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_toolbar.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_toolbar_button.dart';

const _codec = NoteAppFlowyCodec();

NoteBlock _b(String id, String type, [String text = '']) => NoteBlock(
  id: id,
  type: type,
  delta: [
    if (text.isNotEmpty) {'insert': text},
  ],
);

Future<EditorState> _pumpToolbar(
  WidgetTester tester,
  List<NoteBlock> blocks, {
  Selection? selection,
  bool disableAnimations = false,
}) async {
  final editorState = EditorState(document: _codec.toDocument(blocks))
    ..selection = selection ?? Selection.collapsed(Position(path: [0]));
  addTearDown(editorState.dispose);
  Widget child = NoteToolbar(editorState: editorState);
  if (disableAnimations) {
    child = MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: child,
    );
  }
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
  return editorState;
}

ToolbarButton _button(WidgetTester tester, String label) =>
    tester.widget<ToolbarButton>(
      find.ancestor(
        of: find.bySemanticsLabel(label),
        matching: find.byType(ToolbarButton),
      ),
    );

Future<void> _press(WidgetTester tester, String label) async {
  _button(tester, label).onPressed!();
  await tester.pumpAndSettle();
}

String _types(EditorState editorState) =>
    _codec.toBlocks(editorState.document).map((block) => block.type).join(' ');

void main() {
  testWidgets('a caret in a paragraph shows block formats', (tester) async {
    await _pumpToolbar(tester, [_b('p', 'paragraph', 'Olá')]);

    expect(find.bySemanticsLabel('Título 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Negrito'), findsNothing);
  });

  testWidgets('block buttons convert and toggle back', (tester) async {
    final editorState = await _pumpToolbar(tester, [
      _b('p', 'paragraph', 'Olá'),
    ]);

    await _press(tester, 'Título 2');
    expect(_types(editorState), 'header2');
    expect(_button(tester, 'Título 2').isActive, isTrue);

    await _press(tester, 'Título 2');
    expect(_types(editorState), 'paragraph');

    await _press(tester, 'Citação');
    expect(_types(editorState), 'quote');
  });

  testWidgets('the task button switches to the list and task row', (
    tester,
  ) async {
    final editorState = await _pumpToolbar(tester, [
      _b('p', 'paragraph', 'Leite'),
    ]);

    await _press(tester, 'Task');

    expect(_types(editorState), 'task');
    // A caret in a task shows the contextual row.
    expect(find.bySemanticsLabel('Negrito'), findsOneWidget);
    expect(_button(tester, 'Task').isActive, isTrue);
    // Inline formats need selected text; indent is available in a task.
    expect(_button(tester, 'Negrito').onPressed, isNull);
    expect(_button(tester, 'Aumentar recuo').onPressed, isNotNull);
  });

  testWidgets('selected text gets inline formats', (tester) async {
    final editorState = await _pumpToolbar(
      tester,
      [_b('p', 'paragraph', 'negrito')],
      selection: Selection.single(path: [0], startOffset: 0, endOffset: 7),
    );

    await _press(tester, 'Negrito');
    await _press(tester, 'Itálico');

    expect(_codec.toBlocks(editorState.document).single.delta.single, {
      'insert': 'negrito',
      'attributes': {'bold': true, 'italics': true},
    });
    expect(_button(tester, 'Negrito').isActive, isTrue);
    // A paragraph cannot be indented.
    expect(_button(tester, 'Aumentar recuo').onPressed, isNull);
  });

  testWidgets('list buttons convert, and indent nests under the item above', (
    tester,
  ) async {
    final editorState = await _pumpToolbar(
      tester,
      [_b('a', 'bulletList', 'um'), _b('b', 'paragraph', 'dois')],
      selection: Selection.collapsed(Position(path: [1])),
    );

    await _press(tester, 'Task');
    await _press(tester, 'Lista com marcadores');
    expect(_types(editorState), 'bulletList bulletList');

    await _press(tester, 'Aumentar recuo');
    expect(_codec.toBlocks(editorState.document).last.indent, 1);

    await _press(tester, 'Diminuir recuo');
    expect(_codec.toBlocks(editorState.document).last.indent, 0);
  });

  testWidgets('the divider button inserts a divider', (tester) async {
    final editorState = await _pumpToolbar(tester, [_b('p', 'paragraph', 'a')]);
    editorState.selection = Selection.collapsed(Position(path: [0], offset: 1));
    await tester.pumpAndSettle();

    await _press(tester, 'Inserir divisor');

    expect(_types(editorState), 'paragraph divider paragraph');
  });

  testWidgets('the shell stays put while the rows switch', (tester) async {
    final editorState = await _pumpToolbar(tester, [
      _b('p', 'paragraph', 'Hello'),
    ]);
    final shell = find.byKey(const ValueKey('note-toolbar-shell'));
    final before = tester.getTopLeft(shell);

    editorState.selection = Selection.single(
      path: [0],
      startOffset: 0,
      endOffset: 5,
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(shell), before);
    expect(find.bySemanticsLabel('Negrito'), findsOneWidget);
    expect(find.bySemanticsLabel('Título 1'), findsNothing);
  });

  testWidgets('with animations disabled the rows switch instantly', (
    tester,
  ) async {
    final editorState = await _pumpToolbar(
      tester,
      [_b('p', 'paragraph', 'Hello')],
      disableAnimations: true,
    );

    editorState.selection = Selection.single(
      path: [0],
      startOffset: 0,
      endOffset: 5,
    );
    await tester.pump();

    expect(find.bySemanticsLabel('Negrito'), findsOneWidget);
  });
}

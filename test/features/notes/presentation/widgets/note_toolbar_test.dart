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

EditorState _editor(List<NoteBlock> blocks, {Selection? selection}) {
  final editorState = EditorState(document: _codec.toDocument(blocks))
    ..selection = selection ?? Selection.collapsed(Position(path: [0]));
  addTearDown(editorState.dispose);
  return editorState;
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(alignment: Alignment.bottomCenter, child: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _labelled(String label) => find.bySemanticsLabel(label);

ToolbarButton _button(WidgetTester tester, String label) =>
    tester.widget<ToolbarButton>(
      find.ancestor(of: _labelled(label), matching: find.byType(ToolbarButton)),
    );

Future<void> _tap(WidgetTester tester, String label) async {
  // The row scrolls sideways: bring the button into view first.
  await tester.ensureVisible(_labelled(label));
  await tester.pumpAndSettle();
  await tester.tap(_labelled(label));
  await tester.pumpAndSettle();
}

String _types(EditorState editorState) =>
    _codec.toBlocks(editorState.document).map((block) => block.type).join(' ');

void main() {
  testWidgets('every format is in the one row, keyboard button pinned', (
    tester,
  ) async {
    await _pump(
      tester,
      NoteToolbar(editorState: _editor([_b('p', 'paragraph', 'Olá')])),
    );

    for (final label in [
      'Tarefa',
      'Lista com marcadores',
      'Lista numerada',
      'Negrito',
      'Itálico',
      'Tachado',
      'Título',
      'Cabeçalho',
      'Subcabeçalho',
      'Citação',
      'Diminuir recuo',
      'Aumentar recuo',
      'Criar link para outra nota',
      'Inserir divisória',
      'Anexar foto',
      'Anexar arquivo',
      'Esconder teclado',
    ]) {
      expect(_labelled(label), findsOneWidget, reason: label);
    }
    expect(find.text('Formatar'), findsNothing);

    // Scrolling the row leaves the keyboard button where it is.
    final hide = tester.getRect(_labelled('Esconder teclado'));
    await tester.drag(
      find.byKey(const ValueKey('note-toolbar-scroll')),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(_labelled('Esconder teclado')), hide);
  });

  testWidgets('list and task buttons convert the current line', (
    tester,
  ) async {
    final editorState = _editor([_b('p', 'paragraph', 'Leite')]);
    await _pump(tester, NoteToolbar(editorState: editorState));

    await _tap(tester, 'Tarefa');
    expect(_types(editorState), 'task');
    expect(_button(tester, 'Tarefa').isActive, isTrue);

    await _tap(tester, 'Lista com marcadores');
    expect(_types(editorState), 'bulletList');
    await _tap(tester, 'Lista numerada');
    expect(_types(editorState), 'orderedList');
  });

  testWidgets('paragraph styles toggle back to body text', (tester) async {
    final editorState = _editor([_b('p', 'paragraph', 'Oi')]);
    await _pump(tester, NoteToolbar(editorState: editorState));

    await _tap(tester, 'Título');
    expect(_types(editorState), 'header1');
    expect(_button(tester, 'Título').isActive, isTrue);
    await _tap(tester, 'Título');
    expect(_types(editorState), 'paragraph');

    await _tap(tester, 'Citação');
    expect(_types(editorState), 'quote');
  });

  testWidgets('selected text gets inline styles and a note link', (
    tester,
  ) async {
    var linked = false;
    final editorState = _editor(
      [_b('p', 'paragraph', 'negrito')],
      selection: Selection.single(path: [0], startOffset: 0, endOffset: 7),
    );
    await _pump(
      tester,
      NoteToolbar(editorState: editorState, onLinkNote: () => linked = true),
    );

    await _tap(tester, 'Negrito');
    await _tap(tester, 'Itálico');
    expect(_codec.toBlocks(editorState.document).single.delta.single, {
      'insert': 'negrito',
      'attributes': {'bold': true, 'italics': true},
    });
    expect(_button(tester, 'Negrito').isActive, isTrue);

    await _tap(tester, 'Criar link para outra nota');
    expect(linked, isTrue);
  });

  testWidgets('a note link needs selected text', (tester) async {
    await _pump(
      tester,
      NoteToolbar(
        editorState: _editor([_b('p', 'paragraph', 'Oi')]),
        onLinkNote: () {},
      ),
    );
    expect(_button(tester, 'Criar link para outra nota').onPressed, isNull);
  });

  testWidgets('indentation and dividers', (tester) async {
    final editorState = _editor([
      _b('a', 'bulletList', 'um'),
      _b('b', 'bulletList', 'dois'),
    ], selection: Selection.collapsed(Position(path: [1], offset: 4)));
    await _pump(tester, NoteToolbar(editorState: editorState));

    await _tap(tester, 'Aumentar recuo');
    expect(_codec.toBlocks(editorState.document).last.indent, 1);
    await _tap(tester, 'Diminuir recuo');
    expect(_codec.toBlocks(editorState.document).last.indent, 0);

    await _tap(tester, 'Inserir divisória');
    expect(_types(editorState), 'bulletList bulletList divider paragraph');
  });

  testWidgets('indentation is off outside lists and tasks', (tester) async {
    await _pump(
      tester,
      NoteToolbar(editorState: _editor([_b('p', 'paragraph', 'Oi')])),
    );
    expect(_button(tester, 'Aumentar recuo').onPressed, isNull);
  });
}

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_codec.dart';
import 'package:supanotes/features/notes/editor/document/note_blocks.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_format_panel.dart';
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
  await tester.tap(_labelled(label));
  await tester.pumpAndSettle();
}

String _types(EditorState editorState) =>
    _codec.toBlocks(editorState.document).map((block) => block.type).join(' ');

void main() {
  group('toolbar', () {
    testWidgets('a caret shows the writing row', (tester) async {
      await _pump(
        tester,
        NoteToolbar(editorState: _editor([_b('p', 'paragraph', 'Olá')])),
      );

      for (final label in [
        'Formatar',
        'Inserir tarefa',
        'Lista com marcadores',
        'Anexar foto',
        'Anexar arquivo',
        'Esconder teclado',
      ]) {
        expect(_labelled(label), findsOneWidget, reason: label);
      }
      expect(_labelled('Negrito'), findsNothing);
    });

    testWidgets('task and bullet buttons convert the current line', (
      tester,
    ) async {
      final editorState = _editor([_b('p', 'paragraph', 'Leite')]);
      await _pump(tester, NoteToolbar(editorState: editorState));

      await _tap(tester, 'Inserir tarefa');
      expect(_types(editorState), 'task');
      expect(_button(tester, 'Inserir tarefa').isActive, isTrue);

      await _tap(tester, 'Lista com marcadores');
      expect(_types(editorState), 'bulletList');
    });

    testWidgets('selected text shows the selection row and formats it', (
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

      expect(_labelled('Formatar'), findsNothing);
      await _tap(tester, 'Negrito');
      await _tap(tester, 'Itálico');
      expect(_codec.toBlocks(editorState.document).single.delta.single, {
        'insert': 'negrito',
        'attributes': {'bold': true, 'italics': true},
      });
      expect(_button(tester, 'Negrito').isActive, isTrue);

      await _tap(tester, 'Criar link para outra nota');
      expect(linked, isTrue);

      await _tap(tester, 'Transformar em tarefa');
      expect(_types(editorState), 'task');
    });

    testWidgets('Aa toggles the panel and shows when it is open', (
      tester,
    ) async {
      var toggles = 0;
      final editorState = _editor([_b('p', 'paragraph', 'a')]);
      await _pump(
        tester,
        NoteToolbar(editorState: editorState, onTogglePanel: () => toggles++),
      );
      await _tap(tester, 'Formatar');
      expect(toggles, 1);
      expect(_button(tester, 'Formatar').isActive, isFalse);

      await _pump(
        tester,
        NoteToolbar(editorState: editorState, panelOpen: true),
      );
      expect(_button(tester, 'Formatar').isActive, isTrue);
    });

    testWidgets('the bar stays put while the rows switch', (tester) async {
      final editorState = _editor([_b('p', 'paragraph', 'Hello')]);
      await _pump(tester, NoteToolbar(editorState: editorState));
      final shell = find.byKey(const ValueKey('note-toolbar-shell'));
      final before = tester.getRect(shell);

      editorState.selection = Selection.single(
        path: [0],
        startOffset: 0,
        endOffset: 5,
      );
      await tester.pumpAndSettle();

      expect(tester.getRect(shell), before);
      expect(_labelled('Negrito'), findsOneWidget);
    });
  });

  group('format panel', () {
    Future<EditorState> pumpPanel(
      WidgetTester tester,
      List<NoteBlock> blocks, {
      VoidCallback? onClose,
    }) async {
      final editorState = _editor(blocks);
      await _pump(
        tester,
        NoteFormatPanel(
          editorState: editorState,
          height: 320,
          onClose: onClose ?? () {},
        ),
      );
      return editorState;
    }

    testWidgets('paragraph style chips choose a style', (tester) async {
      final editorState = await pumpPanel(tester, [
        _b('p', 'paragraph', 'Oi'),
      ]);

      await _tap(tester, 'Título');
      expect(_types(editorState), 'header1');
      // Choosing the current style keeps it (unlike the toggle buttons).
      await _tap(tester, 'Título');
      expect(_types(editorState), 'header1');

      await _tap(tester, 'Citação');
      expect(_types(editorState), 'quote');
      await _tap(tester, 'Corpo');
      expect(_types(editorState), 'paragraph');
    });

    testWidgets('lists, tasks and dividers', (tester) async {
      final editorState = await pumpPanel(tester, [
        _b('a', 'bulletList', 'um'),
        _b('b', 'paragraph', 'dois'),
      ]);
      editorState.selection = Selection.collapsed(
        Position(path: [1], offset: 4),
      );
      await tester.pumpAndSettle();

      await _tap(tester, 'Lista numerada');
      expect(_types(editorState), 'bulletList orderedList');
      await _tap(tester, 'Lista com marcadores');
      await _tap(tester, 'Aumentar recuo');
      expect(_codec.toBlocks(editorState.document).last.indent, 1);
      await _tap(tester, 'Diminuir recuo');
      expect(_codec.toBlocks(editorState.document).last.indent, 0);

      await _tap(tester, 'Lista de tarefas');
      expect(_types(editorState), 'bulletList task');

      await _tap(tester, 'Inserir divisória');
      expect(_types(editorState), 'bulletList task divider paragraph');
    });

    testWidgets('indentation does nothing outside lists and tasks', (
      tester,
    ) async {
      final editorState = await pumpPanel(tester, [
        _b('p', 'paragraph', 'Oi'),
      ]);

      await _tap(tester, 'Aumentar recuo');

      expect(_types(editorState), 'paragraph');
      expect(_codec.toBlocks(editorState.document).single.indent, 0);
    });

    testWidgets('the close button closes it', (tester) async {
      var closed = false;
      await pumpPanel(tester, [
        _b('p', 'paragraph', 'Oi'),
      ], onClose: () => closed = true);

      await _tap(tester, 'Fechar formatação');
      expect(closed, isTrue);
    });
  });
}

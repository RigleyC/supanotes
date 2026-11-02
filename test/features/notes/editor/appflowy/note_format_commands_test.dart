import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_codec.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_format_commands.dart';
import 'package:supanotes/features/notes/editor/document/note_blocks.dart';

const _codec = NoteAppFlowyCodec();

NoteBlock _b(
  String id,
  String type, [
  String text = '',
  Map<String, dynamic> metadata = const {},
]) => NoteBlock(
  id: id,
  type: type,
  delta: [if (text.isNotEmpty) {'insert': text}],
  metadata: metadata,
);

EditorState _editor(List<NoteBlock> blocks) =>
    EditorState(document: _codec.toDocument(blocks));

List<NoteBlock> _blocks(EditorState editorState) =>
    _codec.toBlocks(editorState.document);

String _shape(EditorState editorState) => _blocks(editorState)
    .map((block) => '${block.id}:${block.type}:${block.indent}')
    .join(' ');

Path _pathOf(EditorState editorState, String id) {
  Node? find(Iterable<Node> nodes) {
    for (final node in nodes) {
      if (node.attributes[NoteNodeKeys.blockId] == id) return node;
      final found = find(node.children);
      if (found != null) return found;
    }
    return null;
  }

  return find(editorState.document.root.children)!.path;
}

void _caret(EditorState editorState, String id, [int offset = 0]) {
  editorState.selection = Selection.collapsed(
    Position(path: _pathOf(editorState, id), offset: offset),
  );
}

void main() {
  test('a block style toggles on and back off, keeping id and caret', () async {
    final editor = _editor([_b('a', 'paragraph', 'Mercado')]);
    _caret(editor, 'a', 3);

    await editor.toggleNoteBlockStyle(NoteBlockStyle.header1);
    expect(_shape(editor), 'a:header1:0');
    expect(NoteFormatState.of(editor).blockStyle, NoteBlockStyle.header1);
    expect(editor.selection!.end.offset, 3);

    await editor.toggleNoteBlockStyle(NoteBlockStyle.header1);
    expect(_shape(editor), 'a:paragraph:0');
    expect(_blocks(editor).single.text, 'Mercado');
  });

  test('leaving a task drops its schedule; entering keeps the indent', () async {
    final editor = _editor([
      _b('l', 'bulletList', 'Lista'),
      _b('t', 'task', 'Leite', {
        'indent': 1,
        'dueDate': '2026-09-16T09:00:00.000',
      }),
    ]);
    _caret(editor, 't');

    await editor.toggleNoteBlockStyle(NoteBlockStyle.bulletList);
    expect(_shape(editor), 'l:bulletList:0 t:bulletList:1');
    expect(_blocks(editor).last.metadata, {'indent': 1});

    await editor.toggleNoteBlockStyle(NoteBlockStyle.task);
    expect(_shape(editor), 'l:bulletList:0 t:task:1');

    await editor.toggleNoteBlockStyle(NoteBlockStyle.task);
    // Paragraphs carry no indent.
    expect(_shape(editor), 'l:bulletList:0 t:paragraph:0');
  });

  test('mixed selection becomes tasks; all tasks toggle off', () async {
    final editor = _editor([
      _b('a', 'paragraph', 'um'),
      _b('b', 'task', 'dois', {'dueDate': '2026-09-16T09:00:00.000'}),
    ]);
    editor.selection = Selection(
      start: Position(path: [0]),
      end: Position(path: [1], offset: 2),
    );

    await editor.toggleNoteBlockStyle(NoteBlockStyle.task);
    expect(_shape(editor), 'a:task:0 b:task:0');
    // The existing task keeps its schedule.
    expect(_blocks(editor).last.metadata['dueDate'], isNotNull);
    expect(NoteFormatState.of(editor).allTasks, isTrue);
  });

  test('indent nests under the block above without reordering', () async {
    final editor = _editor([
      _b('a', 'bulletList', 'a'),
      _b('b', 'bulletList', 'b'),
      _b('c', 'bulletList', 'c'),
    ]);
    _caret(editor, 'b');

    await editor.indentNoteBlocks();
    expect(_shape(editor), 'a:bulletList:0 b:bulletList:1 c:bulletList:0');
    expect(editor.selection!.end.path, [0, 0]);

    // A second indent is not allowed: nothing above is at level 1.
    await editor.indentNoteBlocks();
    expect(_shape(editor), 'a:bulletList:0 b:bulletList:1 c:bulletList:0');
  });

  test('the first block cannot be indented', () async {
    final editor = _editor([_b('a', 'task', 'a')]);
    _caret(editor, 'a');
    await editor.indentNoteBlocks();
    expect(_shape(editor), 'a:task:0');
  });

  test('outdent keeps the reading order of the items below', () async {
    final editor = _editor([
      _b('a', 'task', 'a'),
      _b('x', 'task', 'x', {'indent': 1}),
      _b('y', 'task', 'y', {'indent': 1}),
    ]);
    _caret(editor, 'x');

    await editor.outdentNoteBlocks();
    // AppFlowy's own outdent would move x after y.
    expect(_shape(editor), 'a:task:0 x:task:0 y:task:1');
  });

  test('a divider goes after the caret block, then a line to type on', () async {
    final editor = _editor([_b('a', 'paragraph', 'texto')]);
    _caret(editor, 'a', 5);

    await editor.insertNoteDivider();

    final blocks = _blocks(editor);
    expect(blocks.map((block) => block.type), [
      'paragraph',
      'divider',
      'paragraph',
    ]);
    final index = blocks[1].metadata['dividerIndex'] as int;
    expect(index, inInclusiveRange(1, 35));
    expect(editor.selection!.end.path, [2]);
  });

  test('a divider replaces an empty line', () async {
    final editor = _editor([
      _b('a', 'paragraph', 'texto'),
      _b('e', 'paragraph'),
      _b('c', 'paragraph', 'fim'),
    ]);
    _caret(editor, 'e');

    await editor.insertNoteDivider();

    expect(
      _blocks(editor).map((block) => block.type).join(' '),
      'paragraph divider paragraph',
    );
    expect(_blocks(editor).last.id, 'c');
    expect(editor.selection!.end.path, [2]);
  });

  test('typing --- makes a divider', () async {
    final editor = _editor([_b('a', 'paragraph', '--')]);
    _caret(editor, 'a', 2);

    final handled = await noteDividerShortcut.handler(editor);

    expect(handled, isTrue);
    expect(_blocks(editor).map((block) => block.type), [
      'divider',
      'paragraph',
    ]);
  });

  test('inline styles report what the selection has', () async {
    final editor = _editor([_b('a', 'paragraph', 'negrito')]);
    editor.selection = Selection.single(
      path: [0],
      startOffset: 0,
      endOffset: 7,
    );

    await editor.toggleNoteInlineStyle(NoteInlineStyle.bold);

    expect(NoteFormatState.of(editor).inlineStyles, {NoteInlineStyle.bold});
    expect(_blocks(editor).single.delta.single['attributes'], {'bold': true});
  });

  test('one undo reverts a block conversion', () async {
    final editor = _editor([_b('a', 'paragraph', 'texto')]);
    _caret(editor, 'a');

    await editor.toggleNoteBlockStyle(NoteBlockStyle.quote);
    editor.undoManager.undo();

    expect(_shape(editor), 'a:paragraph:0');
  });
}

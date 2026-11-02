import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_codec.dart';
import 'package:supanotes/features/notes/editor/document/note_blocks.dart';

void main() {
  const codec = NoteAppFlowyCodec();

  final blocks = [
    NoteBlock(
      id: 'title',
      type: 'header1',
      delta: const [
        {'insert': 'Mercado'},
      ],
    ),
    NoteBlock(
      id: 'p',
      type: 'paragraph',
      delta: const [
        {'insert': 'Ver '},
        {
          'insert': 'site',
          'attributes': {'link': 'https://a.dev', 'bold': true},
        },
      ],
    ),
    NoteBlock(
      id: 't1',
      type: 'task',
      delta: const [
        {'insert': 'Leite'},
      ],
      metadata: const {
        'isCompleted': false,
        'dueDate': '2026-09-16T09:00:00.000',
        'hasTime': true,
        'recurrenceRule': 'daily',
        'completions': {'2026-09-15T09:00:00.000': '2026-09-15T12:00:00.000Z'},
      },
    ),
    NoteBlock(
      id: 't2',
      type: 'task',
      delta: const [
        {'insert': 'Desnatado'},
      ],
      metadata: const {'isCompleted': true, 'indent': 1},
    ),
    NoteBlock(
      id: 'b1',
      type: 'bulletList',
      delta: const [
        {'insert': 'Item'},
      ],
    ),
    NoteBlock(
      id: 'b2',
      type: 'orderedList',
      delta: const [
        {'insert': 'Sub'},
      ],
      metadata: const {'indent': 1},
    ),
    NoteBlock(id: 'd', type: 'divider'),
    NoteBlock(
      id: 'a',
      type: 'attachment',
      metadata: const {
        'attachmentId': 'a',
        'filename': 'foto.png',
        'mimeType': 'image/png',
        'fileSize': 10,
      },
    ),
    NoteBlock(
      id: 'q',
      type: 'quote',
      delta: const [
        {'insert': 'Citação'},
      ],
    ),
  ];

  test('round-trips every block type, metadata and indentation', () {
    final document = codec.toDocument(blocks);
    expect(codec.toBlocks(document), blocks);
  });

  test('indented items become nested children in the editor', () {
    final document = codec.toDocument(blocks);
    final parent = document.root.children.elementAt(2);
    expect(parent.type, TodoListBlockKeys.type);
    expect(parent.children.single.attributes[NoteNodeKeys.blockId], 't2');
    expect(document.root.children, hasLength(blocks.length - 2));
  });

  test('an indent without a list parent is flattened', () {
    final orphan = [
      NoteBlock(id: 'p', type: 'paragraph'),
      NoteBlock(id: 't', type: 'task', metadata: const {'indent': 2}),
    ];
    final roundTrip = codec.toBlocks(codec.toDocument(orphan));
    expect(roundTrip.last.indent, 0);
  });

  test('editor-created and duplicated nodes receive fresh ids', () {
    final document = codec.toDocument([blocks.first]);
    final copy = document.root.children.first.copyWith();
    document.insert([1], [copy, paragraphNode(text: 'novo')]);

    final stamped = <String>[];
    final result = codec.toBlocks(
      document,
      idFor: (_) {
        final id = 'new-${stamped.length}';
        stamped.add(id);
        return id;
      },
    );

    expect(result.first.id, 'title');
    expect(stamped, hasLength(2));
    expect(result.map((block) => block.id).toSet(), hasLength(3));
  });

  test('null style attributes left by toggling are dropped', () {
    final document = codec.toDocument([
      NoteBlock(id: 'p', type: 'paragraph'),
    ]);
    final node = document.root.children.first;
    node.updateAttributes({
      'delta': [
        {
          'insert': 'ab',
          'attributes': {'bold': null},
        },
        {'insert': 'c'},
      ],
    });
    expect(codec.toBlocks(document).single.delta, [
      {'insert': 'abc'},
    ]);
  });
}

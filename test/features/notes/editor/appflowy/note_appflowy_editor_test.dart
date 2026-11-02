import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supanotes/features/notes/editor/appflowy/blocks/note_task_block.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_codec.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_editor.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_task_commands.dart';
import 'package:supanotes/features/notes/editor/document/note_blocks.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/attachment_renderers.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_divider_art.dart';
import 'package:supanotes/shared/widgets/app_task_checkbox.dart';

NoteBlock _block(
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

final _blocks = [
  _block('h', 'header1', 'Mercado'),
  _block('p', 'paragraph', 'Comprar hoje'),
  _block('b', 'bulletList', 'Pão'),
  _block('o1', 'orderedList', 'Um'),
  _block('o2', 'orderedList', 'Dois'),
  _block('t1', 'task', 'Leite', {'dueDate': '2026-09-16T09:00:00.000'}),
  _block('t2', 'task', 'Café', {'isCompleted': true}),
  _block('d', 'divider', '', {'dividerIndex': 3}),
  _block('l', 'rich_link', '', {
    'url': 'https://supanotes.app',
    'title': 'SupaNotes',
  }),
];

Future<EditorState> _pumpEditor(
  WidgetTester tester, {
  bool hideCompleted = false,
}) async {
  final editorState = EditorState(
    document: const NoteAppFlowyCodec().toDocument(_blocks),
  );
  addTearDown(editorState.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [AppFlowyEditorLocalizations.delegate],
      home: Scaffold(
        body: NoteAppFlowyEditor(
          editorState: editorState,
          hideCompleted: hideCompleted,
          taskActions: NoteTaskActions(
            onComplete: (id) async {
              await editorState.completeNoteTask(id);
            },
            onReopen: (id, scheduledAt) =>
                editorState.reopenNoteTask(id, scheduledAt: scheduledAt),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return editorState;
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  testWidgets('renders every SupaNotes block type', (tester) async {
    await _pumpEditor(tester);

    expect(find.text('Mercado', findRichText: true), findsOneWidget);
    expect(find.text('Um', findRichText: true), findsOneWidget);
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
    expect(find.byType(AppTaskCheckbox), findsNWidgets(2));
    expect(find.byType(NoteDividerArt), findsOneWidget);
    expect(find.byType(RichLinkCard), findsOneWidget);
  });

  testWidgets('tapping the checkbox completes the task in the document', (
    tester,
  ) async {
    final editorState = await _pumpEditor(tester);

    await tester.tap(find.byType(AppTaskCheckbox).first);
    await tester.pumpAndSettle();

    final task = editorState.nodeForBlock('t1')!;
    expect(task.attributes[TodoListBlockKeys.checked], isTrue);
    // The schedule survives completion.
    expect(
      (task.attributes[NoteNodeKeys.metadata] as Map)['dueDate'],
      '2026-09-16T09:00:00.000',
    );

    await tester.tap(find.byType(AppTaskCheckbox).first);
    await tester.pumpAndSettle();
    expect(task.attributes[TodoListBlockKeys.checked], isFalse);
  });

  testWidgets('hide completed collapses done tasks only', (tester) async {
    await _pumpEditor(tester, hideCompleted: true);

    final hidden = tester.widgetList<IgnorePointer>(
      find.ancestor(
        of: find.text('Café', findRichText: true),
        matching: find.byType(IgnorePointer),
      ),
    );
    expect(hidden.any((widget) => widget.ignoring), isTrue);
    final visible = tester.widgetList<IgnorePointer>(
      find.ancestor(
        of: find.text('Leite', findRichText: true),
        matching: find.byType(IgnorePointer),
      ),
    );
    expect(visible.every((widget) => !widget.ignoring), isTrue);
  });

  test('paragraphs cannot be indented in a note', () {
    configureNoteAppFlowy();
    expect(indentableBlockTypes, isNot(contains(ParagraphBlockKeys.type)));
  });

  test('editor-only inline styles are not stored', () {
    final document = Document.blank()
      ..insert(
        [0],
        [
          paragraphNode(
            delta: Delta()
              ..insert('a', attributes: {'code': true, 'bold': true})
              ..insert('b', attributes: {'font_color': '0xFF0000'}),
          ),
        ],
      );
    final blocks = const NoteAppFlowyCodec().toBlocks(document);
    expect(blocks.single.delta, [
      {
        'insert': 'a',
        'attributes': {'bold': true},
      },
      {'insert': 'b'},
    ]);
  });
}

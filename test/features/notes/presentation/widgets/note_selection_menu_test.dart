import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_codec.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_editor.dart';
import 'package:supanotes/features/notes/editor/document/note_blocks.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_selection_menu.dart';

const _codec = NoteAppFlowyCodec();

NoteBlock _b(
  String id,
  String type,
  String text, [
  Map<String, dynamic>? attributes,
]) => NoteBlock(
  id: id,
  type: type,
  delta: [
    {'insert': text, 'attributes': ?attributes},
  ],
);

List<NoteBlock> _blocks(EditorState editorState) =>
    _codec.toBlocks(editorState.document);

/// The system clipboard, as the platform channel sees it.
String? _clipboard;
final _menuCalls = <MethodCall>[];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _clipboard = null;
    _menuCalls.clear();
    NoteClipboard.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              _clipboard = (call.arguments as Map)['text'] as String?;
            case 'Clipboard.getData':
              return _clipboard == null ? null : {'text': _clipboard};
            case 'ContextMenu.showSystemContextMenu':
            case 'ContextMenu.hideSystemContextMenu':
              _menuCalls.add(call);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('NoteClipboard', () {
    EditorState editor(List<NoteBlock> blocks) {
      final editorState = EditorState(document: _codec.toDocument(blocks));
      addTearDown(editorState.dispose);
      return editorState;
    }

    test('copy and paste keep formatting and blocks across lines', () async {
      final editorState = editor([
        _b('h', 'header2', 'Mercado'),
        _b('p', 'paragraph', 'leite', {'bold': true}),
        _b('t', 'task', 'pão'),
        _b('e', 'paragraph', 'fim'),
      ]);
      editorState.selection = Selection(
        start: Position(path: [1]),
        end: Position(path: [2], offset: 3),
      );

      await NoteClipboard.copy(editorState);
      expect(_clipboard, 'leite\npão');

      editorState.selection = Selection.collapsed(
        Position(path: [3], offset: 3),
      );
      await NoteClipboard.paste(editorState);

      final blocks = _blocks(editorState);
      expect(blocks.map((block) => block.type), [
        'header2',
        'paragraph',
        'task',
        'paragraph',
        'task',
      ]);
      // The bold text joins the line it is pasted into; the task stays a task.
      expect(blocks[3].delta.last, {
        'insert': 'leite',
        'attributes': {'bold': true},
      });
      expect(blocks[4].text, 'pão');
      // Pasted blocks are new blocks, not a second copy of the originals.
      expect(blocks[4].id, isNot('t'));
      expect(blocks.map((block) => block.id).toSet(), hasLength(5));
    });

    test('text copied elsewhere is pasted as plain paragraphs', () async {
      final editorState = editor([_b('p', 'paragraph', 'a')]);
      _clipboard = 'um\ndois';
      editorState.selection = Selection.collapsed(
        Position(path: [0], offset: 1),
      );

      await NoteClipboard.paste(editorState);

      final blocks = _blocks(editorState);
      expect(blocks.map((block) => block.text), ['aum', 'dois']);
      expect(blocks.map((block) => block.type).toSet(), {'paragraph'});
    });

    test('cut copies, then removes the selection', () async {
      final editorState = editor([_b('p', 'paragraph', 'recortar isto')]);
      editorState.selection = Selection.single(
        path: [0],
        startOffset: 0,
        endOffset: 9,
      );

      await NoteClipboard.cut(editorState);

      expect(_clipboard, 'recortar ');
      expect(_blocks(editorState).single.text, 'isto');
    });

    test('select all covers the whole note', () {
      final editorState = editor([
        _b('a', 'paragraph', 'um'),
        _b('b', 'task', 'dois'),
      ]);
      editorState.selection = Selection.collapsed(Position(path: [0]));

      NoteClipboard.selectAll(editorState);

      expect(editorState.selection!.start, Position(path: [0]));
      expect(editorState.selection!.end, Position(path: [1], offset: 4));
    });
  });

  group('menu', () {
    late EditorState editorState;
    late ValueNotifier<bool> editing;

    Future<NoteSelectionMenuState> pumpMenu(
      WidgetTester tester, {
      bool systemMenu = false,
    }) async {
      editorState = EditorState(
        document: _codec.toDocument([
          _b('a', 'paragraph', 'primeira linha'),
          _b('b', 'paragraph', 'segunda linha'),
        ]),
      );
      editing = ValueNotifier(true);
      addTearDown(editorState.dispose);
      addTearDown(editing.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppFlowyEditorLocalizations.delegate],
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(supportsShowingSystemContextMenu: systemMenu),
              child: Scaffold(
                body: NoteSelectionMenu(
                  editorState: editorState,
                  editing: editing,
                  child: NoteAppFlowyEditor(editorState: editorState),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.state<NoteSelectionMenuState>(
        find.byType(NoteSelectionMenu),
      );
    }

    Future<void> select(
      WidgetTester tester,
      Selection selection, {
      Map<String, dynamic>? extraInfo,
    }) async {
      editorState.updateSelectionWithReason(
        selection,
        reason: SelectionUpdateReason.uiEvent,
        extraInfo: extraInfo,
      );
      await tester.pumpAndSettle();
    }

    final word = Selection.single(path: [0], startOffset: 0, endOffset: 8);

    testWidgets('shows for selected text with copy, cut, paste and all', (
      tester,
    ) async {
      final menu = await pumpMenu(tester);

      await select(tester, word);

      expect(menu.isVisible, isTrue);
      expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
      for (final label in ['Cut', 'Copy', 'Paste', 'Select all']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(_clipboard, 'primeira');
      expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
    });

    testWidgets('stays hidden while a handle is dragged', (tester) async {
      final menu = await pumpMenu(tester);

      await select(
        tester,
        word,
        extraInfo: {'selection_drag_mode': _DragMode.rightSelectionHandle},
      );
      expect(menu.isVisible, isFalse);

      // Letting go of the handle shows it.
      await select(
        tester,
        Selection.single(path: [0], startOffset: 0, endOffset: 9),
        extraInfo: {'selection_drag_mode': _DragMode.none},
      );
      expect(menu.isVisible, isTrue);
    });

    testWidgets('typing or moving the caret hides it; tapping the caret '
        'again offers paste', (tester) async {
      final menu = await pumpMenu(tester);
      await select(tester, word);
      expect(menu.isVisible, isTrue);

      final caret = Selection.collapsed(Position(path: [1], offset: 3));
      await select(tester, caret);
      expect(menu.isVisible, isFalse);

      await select(tester, caret);
      expect(menu.isVisible, isTrue);
      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('Copy'), findsNothing);
    });

    testWidgets('only while editing', (tester) async {
      final menu = await pumpMenu(tester);
      await select(tester, word);
      expect(menu.isVisible, isTrue);

      editing.value = false;
      await tester.pumpAndSettle();
      expect(menu.isVisible, isFalse);

      await select(
        tester,
        Selection.single(path: [1], startOffset: 0, endOffset: 7),
      );
      expect(menu.isVisible, isFalse);
    });

    testWidgets('on iOS it is the system menu with the note actions', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await pumpMenu(tester, systemMenu: true);
        await select(tester, word);

        final show = _menuCalls.lastWhere(
          (call) => call.method == 'ContextMenu.showSystemContextMenu',
        );
        final items = ((show.arguments as Map)['items'] as List)
            .cast<Map<Object?, Object?>>();
        final titles = [for (final item in items) item['title']];
        expect(
          titles,
          containsAllInOrder([
            'Recortar',
            'Copiar',
            'Colar',
            'Selecionar tudo',
          ]),
        );
        expect(
          items.map((item) => item['type']),
          containsAll(['lookUp', 'searchWeb', 'share']),
        );
        expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}

/// Mirrors AppFlowy's drag modes by name, as the menu reads them.
enum _DragMode { none, rightSelectionHandle }

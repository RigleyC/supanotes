// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irondash_message_channel/irondash_message_channel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/clipboard_preprocessor.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/rich_clipboard_serializers.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/rich_common_editor_operations.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/rich_keyboard_actions.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor_clipboard/super_editor_clipboard.dart';
import 'package:super_native_extensions/src/native/context.dart';

class MockEditor extends Mock implements Editor {}

class MockDocumentLayout extends Mock implements DocumentLayout {}

class MockClipboard extends Mock implements SystemClipboard {}

class MockClipboardReader extends Mock implements ClipboardReader {}

class MockClipboardDataReader extends Mock implements ClipboardDataReader {}

void _stubNoBitmapFormats(MockClipboardReader reader) {
  when(() => reader.canProvide(Formats.png)).thenReturn(false);
  when(() => reader.canProvide(Formats.jpeg)).thenReturn(false);
  when(() => reader.canProvide(Formats.heic)).thenReturn(false);
  when(() => reader.canProvide(Formats.gif)).thenReturn(false);
  when(() => reader.canProvide(Formats.bmp)).thenReturn(false);
  when(() => reader.canProvide(Formats.webp)).thenReturn(false);
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    final mockContext =
        superNativeExtensionsContext as MockMessageChannelContext;
    mockContext.registerMockMethodCallHandler('DataProviderManager', (
      call,
    ) async {
      if (call.method == 'registerDataProvider') {
        return 1;
      }
      return null;
    });
    mockContext.registerMockMethodCallHandler('ClipboardWriter', (call) async {
      if (call.method == 'writeToClipboard') {
        return null;
      }
      return null;
    });
    mockContext.registerMockMethodCallHandler('ClipboardReader', (call) async {
      if (call.method == 'newClipboardReader') {
        return {'handle': 1, 'finalizableHandle': 0};
      }
      return null;
    });
    mockContext.registerMockMethodCallHandler('ReaderManager', (call) async {
      if (call.method == 'getItems') {
        return [];
      }
      return null;
    });
  });

  group('clipboard serialization', () {
    test('normalizes spaces after plain-text list markers', () {
      expect(
        preprocessClipboardText('-    Texto colado aqui'),
        '- Texto colado aqui',
      );
      expect(preprocessClipboardText('*   Outro item'), '* Outro item');
      expect(preprocessClipboardText('1.   Item ordenado'), '1. Item ordenado');
    });

    test('rich HTML includes headings, lists, and tasks', () {
      configureRichClipboardSerializers();
      final document = MutableDocument(
        nodes: [
          ParagraphNode(
            id: 'heading',
            text: AttributedText('Título'),
            metadata: const {'blockType': header1Attribution},
          ),
          ListItemNode.unordered(id: 'list-item', text: AttributedText('Item')),
          TaskNode(
            id: 'task',
            text: AttributedText('Tarefa'),
            isComplete: false,
          ),
        ],
      );

      final html = document.toHtml(
        nodeSerializers: SuperEditorClipboardConfig.nodeHtmlSerializers,
        inlineSerializers: SuperEditorClipboardConfig.inlineHtmlSerializers,
      );

      expect(html, contains('<h1>'));
      expect(html, contains('<ul>'));
      expect(html, contains('type="checkbox"'));
      expect(html, contains('Tarefa'));
    });

    test('task copied as HTML pastes back as a task', () {
      configureRichClipboardSerializers();
      final source = MutableDocument(
        nodes: [
          TaskNode(
            id: 'task',
            text: AttributedText('Tarefa'),
            isComplete: false,
          ),
        ],
      );
      final markdown = clipboardHtmlToMarkdown(
        source.toHtml(
          nodeSerializers: SuperEditorClipboardConfig.nodeHtmlSerializers,
          inlineSerializers: SuperEditorClipboardConfig.inlineHtmlSerializers,
        ),
      );
      expect(markdown, matches(RegExp(r'[-*] \[ \] Tarefa')));
      final target = MutableDocument(
        nodes: [ParagraphNode(id: 'target', text: AttributedText())],
      );
      final composer = MutableDocumentComposer(
        initialSelection: const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: 'target',
            nodePosition: TextNodePosition(offset: 0),
          ),
        ),
      );
      final editor = createDefaultDocumentEditor(
        document: target,
        composer: composer,
      );

      editor.pasteMarkdown(editor, markdown);

      final pastedTasks = target.toList().whereType<TaskNode>().toList();
      expect(pastedTasks, hasLength(1));
      expect(pastedTasks.single.text.toPlainText(), 'Tarefa');
    });

    test('single-line text pasted inside a task stays in the task', () {
      final document = MutableDocument(
        nodes: [
          TaskNode(
            id: 'task',
            text: AttributedText('Comprar '),
            isComplete: false,
          ),
        ],
      );
      final composer = MutableDocumentComposer(
        initialSelection: const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: 'task',
            nodePosition: TextNodePosition(offset: 8),
          ),
        ),
      );
      final editor = createDefaultDocumentEditor(
        document: document,
        composer: composer,
      );

      expect(pastePlainTextAtCurrentSelection(editor, 'leite'), isTrue);

      expect(document.nodeCount, 1);
      expect(document.first, isA<TaskNode>());
      expect((document.first as TaskNode).text.toPlainText(), 'Comprar leite');
    });

    test(
      'preprocessed paste delegates task HTML to Markdown parsing',
      () async {
        final document = MutableDocument(
          nodes: [ParagraphNode(id: 'target', text: AttributedText())],
        );
        final composer = MutableDocumentComposer(
          initialSelection: const DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: 'target',
              nodePosition: TextNodePosition(offset: 0),
            ),
          ),
        );
        final editor = createDefaultDocumentEditor(
          document: document,
          composer: composer,
        );
        final htmlItem = MockClipboardDataReader();
        final reader = MockClipboardReader();
        final clipboard = MockClipboard();

        const html = '<ul><li><input type="checkbox"> Tarefa</li></ul>';
        when(clipboard.read).thenAnswer((_) async => reader);
        when(() => reader.items).thenReturn([htmlItem]);
        _stubNoBitmapFormats(reader);
        when(() => htmlItem.canProvide(Formats.md)).thenReturn(false);
        when(() => htmlItem.canProvide(Formats.htmlText)).thenReturn(true);
        when(
          () => htmlItem.readValue<String>(Formats.htmlText),
        ).thenAnswer((_) async => html);

        await pasteWithPreprocessing(editor, testClipboard: clipboard);

        final tasks = document.toList().whereType<TaskNode>().toList();
        expect(tasks, hasLength(1));
        expect(tasks.single.text.toPlainText(), 'Tarefa');
      },
    );

    test(
      'preprocessed plain text still uses the package dispatch chain',
      () async {
        final document = MutableDocument(
          nodes: [ParagraphNode(id: 'target', text: AttributedText())],
        );
        final composer = MutableDocumentComposer(
          initialSelection: const DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: 'target',
              nodePosition: TextNodePosition(offset: 0),
            ),
          ),
        );
        final editor = createDefaultDocumentEditor(
          document: document,
          composer: composer,
        );
        final plainItem = MockClipboardDataReader();
        final reader = MockClipboardReader();
        final clipboard = MockClipboard();

        when(clipboard.read).thenAnswer((_) async => reader);
        when(() => reader.items).thenReturn([plainItem]);
        _stubNoBitmapFormats(reader);
        when(() => reader.canProvide(Formats.plainText)).thenReturn(true);
        when(
          () => reader.readValue<String>(Formats.plainText),
        ).thenAnswer((_) async => 'Texto colado');
        when(() => plainItem.canProvide(Formats.md)).thenReturn(false);
        when(() => plainItem.canProvide(Formats.htmlText)).thenReturn(false);
        when(() => plainItem.canProvide(Formats.uri)).thenReturn(false);

        await pasteWithPreprocessing(editor, testClipboard: clipboard);

        expect(document.first, isA<ParagraphNode>());
        expect(
          (document.first as ParagraphNode).text.toPlainText(),
          'Texto colado',
        );
      },
    );

    test('preprocessed paste preserves the package URL fallback', () async {
      final document = MutableDocument(
        nodes: [ParagraphNode(id: 'target', text: AttributedText())],
      );
      final composer = MutableDocumentComposer(
        initialSelection: const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: 'target',
            nodePosition: TextNodePosition(offset: 0),
          ),
        ),
      );
      final editor = createDefaultDocumentEditor(
        document: document,
        composer: composer,
      );
      final urlItem = MockClipboardDataReader();
      final reader = MockClipboardReader();
      final clipboard = MockClipboard();
      final uri = Uri.parse('https://example.com/note');

      when(clipboard.read).thenAnswer((_) async => reader);
      when(() => reader.items).thenReturn([urlItem]);
      _stubNoBitmapFormats(reader);
      when(() => reader.canProvide(Formats.plainText)).thenReturn(false);
      when(() => urlItem.canProvide(Formats.md)).thenReturn(false);
      when(() => urlItem.canProvide(Formats.htmlText)).thenReturn(false);
      when(() => urlItem.canProvide(Formats.uri)).thenReturn(true);
      when(
        () => urlItem.readValue<NamedUri>(Formats.uri),
      ).thenAnswer((_) async => NamedUri(uri));

      await pasteWithPreprocessing(editor, testClipboard: clipboard);

      expect(
        (document.first as ParagraphNode).text.toPlainText(),
        uri.toString(),
      );
    });

    test('preprocessed plain text replaces an expanded selection', () async {
      final document = MutableDocument(
        nodes: [ParagraphNode(id: 'target', text: AttributedText('Hello'))],
      );
      final composer = MutableDocumentComposer(
        initialSelection: const DocumentSelection(
          base: DocumentPosition(
            nodeId: 'target',
            nodePosition: TextNodePosition(offset: 0),
          ),
          extent: DocumentPosition(
            nodeId: 'target',
            nodePosition: TextNodePosition(offset: 5),
          ),
        ),
      );
      final editor = createDefaultDocumentEditor(
        document: document,
        composer: composer,
      );
      final plainItem = MockClipboardDataReader();
      final reader = MockClipboardReader();
      final clipboard = MockClipboard();

      when(clipboard.read).thenAnswer((_) async => reader);
      when(() => reader.items).thenReturn([plainItem]);
      _stubNoBitmapFormats(reader);
      when(() => reader.canProvide(Formats.plainText)).thenReturn(true);
      when(
        () => reader.readValue<String>(Formats.plainText),
      ).thenAnswer((_) async => 'World');
      when(() => plainItem.canProvide(Formats.md)).thenReturn(false);
      when(() => plainItem.canProvide(Formats.htmlText)).thenReturn(false);
      when(() => plainItem.canProvide(Formats.uri)).thenReturn(false);

      await pasteWithPreprocessing(editor, testClipboard: clipboard);

      expect((document.first as ParagraphNode).text.toPlainText(), 'World');
    });
  });

  group('Rich Keyboard Actions', () {
    test('buildRichKeyboardActions prepends rich clipboard actions', () {
      final baseActions = <SuperEditorKeyboardAction>[
        doNothingWhenThereIsNoSelection,
      ];

      final richActions = buildRichKeyboardActions(baseActions: baseActions);

      expect(richActions.length, equals(5));
      expect(
        richActions[0],
        equals(copyAsRichTextWithMarkdownFallbackWhenShortcutIsPressed),
      );
      expect(richActions[1], equals(cutAsRichTextWhenCmdXOrCtrlXIsPressed));
      expect(richActions[2], equals(pastePreprocessedRichText));
      expect(richActions[3], equals(insertEmptyTaskBeforeMetadataTaskOnEnter));
      expect(richActions[4], equals(doNothingWhenThereIsNoSelection));
    });

    test('enter at task start keeps metadata with the task text', () {
      final original = TaskNode(
        id: 'task-1',
        text: AttributedText('Comprar leite'),
        isComplete: false,
        indent: 2,
        metadata: const {
          'dueDate': '2026-07-30T10:00:00.000',
          'hasTime': true,
          'recurrenceRule': 'daily',
          'reminder': '15m_before',
        },
      );
      final document = MutableDocument(nodes: [original]);
      final composer = MutableDocumentComposer(
        initialSelection: const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: 'task-1',
            nodePosition: TextNodePosition(offset: 0),
          ),
        ),
      );
      final editor = createDefaultDocumentEditor(
        document: document,
        composer: composer,
      );
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      final layout = MockDocumentLayout();
      final editContext = SuperEditorContext(
        editorFocusNode: focusNode,
        editor: editor,
        document: document,
        getDocumentLayout: () => layout,
        composer: composer,
        scroller: DocumentScroller(),
        commonOps: CommonEditorOperations(
          editor: editor,
          document: document,
          composer: composer,
          documentLayoutResolver: () => layout,
        ),
      );

      final result = insertEmptyTaskBeforeMetadataTaskOnEnter(
        editContext: editContext,
        keyEvent: const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.enter,
          logicalKey: LogicalKeyboardKey.enter,
          timeStamp: Duration.zero,
        ),
      );

      expect(result, ExecutionInstruction.haltExecution);
      final tasks = document.toList().whereType<TaskNode>().toList();
      expect(tasks, hasLength(2));
      expect(tasks.first.text.toPlainText(), isEmpty);
      expect(tasks.first.metadata.containsKey('dueDate'), isFalse);
      expect(tasks.first.metadata.containsKey('hasTime'), isFalse);
      expect(tasks.first.metadata.containsKey('recurrenceRule'), isFalse);
      expect(tasks.first.metadata.containsKey('reminder'), isFalse);
      expect(tasks.first.indent, 2);
      expect(tasks.last.id, 'task-1');
      expect(tasks.last.text.toPlainText(), 'Comprar leite');
      expect(tasks.last.metadata, original.metadata);
      expect(composer.selection!.extent.nodeId, tasks.first.id);
    });
  });

  group('RichCommonEditorOperations', () {
    late MockEditor editor;
    late MutableDocument document;
    late MutableDocumentComposer composer;
    late RichCommonEditorOperations operations;

    setUp(() {
      editor = MockEditor();
      document = MutableDocument(
        nodes: [
          ParagraphNode(id: 'node-1', text: AttributedText('Hello World')),
        ],
      );
      composer = MutableDocumentComposer();

      final editContext = EditContext({
        Editor.documentKey: document,
        Editor.composerKey: composer,
      });
      when(() => editor.context).thenReturn(editContext);
      when(() => editor.execute(any())).thenAnswer((_) {});

      operations = RichCommonEditorOperations(
        editor: editor,
        document: document,
        composer: composer,
        documentLayoutResolver: MockDocumentLayout.new,
      );
    });

    test('copy does not throw when selection is null', () {
      composer.setSelectionWithReason(null);
      expect(() => operations.copy(), returnsNormally);
    });

    test('cut does not throw when selection is null', () {
      composer.setSelectionWithReason(null);
      expect(() => operations.cut(), returnsNormally);
    });

    test('copy does not copy when selection is collapsed', () {
      const selection = DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: 'node-1',
          nodePosition: TextNodePosition(offset: 0),
        ),
      );
      composer.setSelectionWithReason(selection);
      expect(() => operations.copy(), returnsNormally);
    });

    test('cut does not cut when selection is collapsed', () {
      const selection = DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: 'node-1',
          nodePosition: TextNodePosition(offset: 0),
        ),
      );
      composer.setSelectionWithReason(selection);
      expect(() => operations.cut(), returnsNormally);
    });

    test('copy with non-collapsed selection does not throw', () {
      const selection = DocumentSelection(
        base: DocumentPosition(
          nodeId: 'node-1',
          nodePosition: TextNodePosition(offset: 0),
        ),
        extent: DocumentPosition(
          nodeId: 'node-1',
          nodePosition: TextNodePosition(offset: 5),
        ),
      );
      composer.setSelectionWithReason(selection);
      expect(() => operations.copy(), returnsNormally);
    });

    test('cut with non-collapsed selection does not throw', () {
      const selection = DocumentSelection(
        base: DocumentPosition(
          nodeId: 'node-1',
          nodePosition: TextNodePosition(offset: 0),
        ),
        extent: DocumentPosition(
          nodeId: 'node-1',
          nodePosition: TextNodePosition(offset: 5),
        ),
      );
      composer.setSelectionWithReason(selection);

      expect(() => operations.cut(), returnsNormally);
      verify(() => editor.execute(any())).called(1);
    });

    test('paste does not throw', () {
      expect(() => operations.paste(), returnsNormally);
    });
  });
}

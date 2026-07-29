// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor_clipboard/super_editor_clipboard.dart';
import 'package:super_native_extensions/src/native/context.dart';
import 'package:irondash_message_channel/irondash_message_channel.dart';
import 'package:supanotes/features/notes/presentation/widgets/rich_keyboard_actions.dart';
import 'package:supanotes/features/notes/presentation/widgets/rich_common_editor_operations.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/rich_clipboard_serializers.dart';
import 'package:supanotes/features/notes/presentation/widgets/clipboard_preprocessor.dart';
import 'package:supanotes/features/notes/presentation/widgets/slash_command_overlay.dart';

class MockEditor extends Mock implements Editor {}

class MockDocumentLayout extends Mock implements DocumentLayout {}

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
            metadata: {'blockType': header1Attribution},
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
  });

  group('Rich Keyboard Actions', () {
    test('buildRichKeyboardActions prepends rich clipboard actions', () {
      final baseActions = <SuperEditorKeyboardAction>[
        doNothingWhenThereIsNoSelection,
      ];

      final richActions = buildRichKeyboardActions(baseActions: baseActions);

      expect(richActions.length, equals(4));
      expect(
        richActions[0],
        equals(copyAsRichTextWithMarkdownFallbackWhenShortcutIsPressed),
      );
      expect(richActions[1], equals(cutAsRichTextWhenCmdXOrCtrlXIsPressed));
      expect(richActions[2], equals(pastePreprocessedRichText));
      expect(richActions[3], equals(doNothingWhenThereIsNoSelection));
    });

    test(
      'buildRichKeyboardActions injects slash handler when scoped controller exists',
      () {
        final baseActions = <SuperEditorKeyboardAction>[
          doNothingWhenThereIsNoSelection,
        ];
        final slashController = SlashCommandController();
        addTearDown(slashController.dispose);

        final richActions = buildRichKeyboardActions(
          baseActions: baseActions,
          slashCommandController: slashController,
        );

        expect(richActions.length, equals(5));
        expect(
          richActions[1],
          equals(copyAsRichTextWithMarkdownFallbackWhenShortcutIsPressed),
        );
        expect(richActions[2], equals(cutAsRichTextWhenCmdXOrCtrlXIsPressed));
        expect(richActions[3], equals(pastePreprocessedRichText));
        expect(richActions[4], equals(doNothingWhenThereIsNoSelection));
      },
    );
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
        documentLayoutResolver: () => MockDocumentLayout(),
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
      final selection = DocumentSelection.collapsed(
        position: const DocumentPosition(
          nodeId: 'node-1',
          nodePosition: TextNodePosition(offset: 0),
        ),
      );
      composer.setSelectionWithReason(selection);
      expect(() => operations.copy(), returnsNormally);
    });

    test('cut does not cut when selection is collapsed', () {
      final selection = DocumentSelection.collapsed(
        position: const DocumentPosition(
          nodeId: 'node-1',
          nodePosition: TextNodePosition(offset: 0),
        ),
      );
      composer.setSelectionWithReason(selection);
      expect(() => operations.cut(), returnsNormally);
    });

    test('copy with non-collapsed selection does not throw', () {
      final selection = DocumentSelection(
        base: const DocumentPosition(
          nodeId: 'node-1',
          nodePosition: TextNodePosition(offset: 0),
        ),
        extent: const DocumentPosition(
          nodeId: 'node-1',
          nodePosition: TextNodePosition(offset: 5),
        ),
      );
      composer.setSelectionWithReason(selection);
      expect(() => operations.copy(), returnsNormally);
    });

    test('cut with non-collapsed selection does not throw', () {
      final selection = DocumentSelection(
        base: const DocumentPosition(
          nodeId: 'node-1',
          nodePosition: TextNodePosition(offset: 0),
        ),
        extent: const DocumentPosition(
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

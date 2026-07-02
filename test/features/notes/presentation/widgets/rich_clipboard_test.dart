// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor_clipboard/super_editor_clipboard.dart';
import 'package:super_native_extensions/src/native/context.dart';
import 'package:irondash_message_channel/irondash_message_channel.dart';
import 'package:supanotes/features/notes/presentation/widgets/rich_keyboard_actions.dart';
import 'package:supanotes/features/notes/presentation/widgets/rich_common_editor_operations.dart';

class MockEditor extends Mock implements Editor {}
class MockDocumentLayout extends Mock implements DocumentLayout {}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    final mockContext = superNativeExtensionsContext as MockMessageChannelContext;
    mockContext.registerMockMethodCallHandler('DataProviderManager', (call) async {
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
        return {
          'handle': 1,
          'finalizableHandle': 0,
        };
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

  group('Rich Keyboard Actions', () {
    test('buildRichKeyboardActions prepends rich clipboard actions at the start of actions list', () {
      final baseActions = <SuperEditorKeyboardAction>[
        doNothingWhenThereIsNoSelection,
      ];

      final richActions = buildRichKeyboardActions(baseActions: baseActions);

      expect(richActions.length, equals(4));
      expect(richActions[0], equals(copyAsRichTextWhenCmdCOrCtrlCIsPressed));
      expect(richActions[1], equals(cutAsRichTextWhenCmdXOrCtrlXIsPressed));
      expect(richActions[2], equals(pastePreprocessedRichText));
      expect(richActions[3], equals(doNothingWhenThereIsNoSelection));
    });
  });

  group('RichCommonEditorOperations', () {
    late MockEditor editor;
    late MutableDocument document;
    late MutableDocumentComposer composer;
    late RichCommonEditorOperations operations;

    setUp(() {
      editor = MockEditor();
      document = MutableDocument(nodes: [
        ParagraphNode(id: 'node-1', text: AttributedText('Hello World')),
      ]);
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

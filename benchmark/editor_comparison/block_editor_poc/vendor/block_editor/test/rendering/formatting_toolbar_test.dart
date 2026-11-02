import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:block_editor/block_editor.dart';

BlockController _ctrl(List<BlockNode> blocks) =>
    BlockController(document: BlockDocument(blocks));

BlockNode _para(String id, String text, {InlineAttributes? attrs}) => BlockNode(
  id: id,
  type: BlockTypes.paragraph,
  delta: TextDelta([
    TextOp(text, attributes: attrs ?? const InlineAttributes()),
  ]),
);

BlockNode _mixed(String id) => BlockNode(
  id: id,
  type: BlockTypes.paragraph,
  delta: TextDelta([
    const TextOp('hello', attributes: InlineAttributes(bold: true)),
    const TextOp(' world'),
  ]),
);

void _expand(BlockController ctrl, String id, int start, int end) {
  ctrl.updateSelection(
    ExpandedSelection(
      anchor: SelectionPoint(blockId: id, offset: start),
      focus: SelectionPoint(blockId: id, offset: end),
    ),
  );
}

void main() {
  group('FormattingToolbar — renders when ExpandedSelection is active', () {
    testWidgets('toolbar is present with expanded selection', (tester) async {
      final ctrl = _ctrl([_para('a', 'hello world')]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BlockEditorWidget(controller: ctrl)),
        ),
      );

      _expand(ctrl, 'a', 0, 5);
      await tester.pump();

      expect(find.byType(FormattingToolbar), findsOneWidget);
    });

    testWidgets('toolbar is absent when readOnly is true', (tester) async {
      final ctrl = _ctrl([_para('a', 'hello world')]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockEditorWidget(controller: ctrl, readOnly: true),
          ),
        ),
      );

      _expand(ctrl, 'a', 0, 5);
      await tester.pump();

      expect(find.byType(FormattingToolbar), findsNothing);
    });

    testWidgets('toolbar disappears when selection collapses', (tester) async {
      final ctrl = _ctrl([_para('a', 'hello world')]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BlockEditorWidget(controller: ctrl)),
        ),
      );

      _expand(ctrl, 'a', 0, 5);
      await tester.pump();
      expect(find.byType(FormattingToolbar), findsOneWidget);

      ctrl.collapseSelection('a', 3);
      await tester.pump();

      expect(find.byType(FormattingToolbar), findsNothing);
    });
  });

  group('FormattingToolbar — button rendering', () {
    testWidgets('all eight buttons are present', (tester) async {
      final ctrl = _ctrl([_para('a', 'hello world')]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BlockEditorWidget(controller: ctrl)),
        ),
      );

      _expand(ctrl, 'a', 0, 5);
      await tester.pump();

      expect(find.byIcon(Icons.format_bold), findsOneWidget);
      expect(find.byIcon(Icons.format_italic), findsOneWidget);
      expect(find.byIcon(Icons.format_underline), findsOneWidget);
      expect(find.byIcon(Icons.format_strikethrough), findsOneWidget);
      expect(find.byIcon(Icons.code), findsOneWidget);
      expect(find.byIcon(Icons.link), findsOneWidget);
      expect(find.byIcon(Icons.format_color_text), findsOneWidget);
      expect(find.byIcon(Icons.format_color_fill), findsOneWidget);
    });

    testWidgets('bold button applies bold to selection', (tester) async {
      final ctrl = _ctrl([_para('a', 'hello world')]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BlockEditorWidget(controller: ctrl)),
        ),
      );

      _expand(ctrl, 'a', 0, 5);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.format_bold));
      await tester.pump();

      final node = ctrl.document.findById('a')!;
      final first = node.delta!.ops.first as TextOp;
      expect(first.attributes.bold, true);
    });
  });

  group('EditorEditingOperations — applyStrikethrough', () {
    test('applies strikethrough to expanded selection', () {
      final ctrl = _ctrl([_para('a', 'hello')]);
      ctrl.updateSelection(
        const ExpandedSelection(
          anchor: SelectionPoint(blockId: 'a', offset: 0),
          focus: SelectionPoint(blockId: 'a', offset: 5),
        ),
      );
      final ops = EditorEditingOperations(ctrl);

      ops.applyStrikethrough();

      final node = ctrl.document.findById('a')!;
      final op = node.delta!.ops.first as TextOp;
      expect(op.attributes.strikethrough, true);
    });

    test('does nothing when selection is collapsed', () {
      final ctrl = _ctrl([_para('a', 'hello')]);
      ctrl.collapseSelection('a', 2);
      final ops = EditorEditingOperations(ctrl);

      ops.applyStrikethrough();

      final node = ctrl.document.findById('a')!;
      final op = node.delta!.ops.first as TextOp;
      expect(op.attributes.strikethrough, isNull);
    });
  });

  group('EditorEditingOperations — applyInlineCode', () {
    test('applies inlineCode formatting to expanded selection', () {
      final ctrl = _ctrl([_para('a', 'hello')]);
      ctrl.updateSelection(
        const ExpandedSelection(
          anchor: SelectionPoint(blockId: 'a', offset: 0),
          focus: SelectionPoint(blockId: 'a', offset: 5),
        ),
      );
      final ops = EditorEditingOperations(ctrl);

      ops.applyInlineCode();

      final node = ctrl.document.findById('a')!;
      final op = node.delta!.ops.first as TextOp;
      expect(op.attributes.inlineCode, true);
    });
  });

  group('EditorEditingOperations — applyAttributes', () {
    test('applies hex color string to selection', () {
      final ctrl = _ctrl([_para('a', 'hello')]);
      ctrl.updateSelection(
        const ExpandedSelection(
          anchor: SelectionPoint(blockId: 'a', offset: 0),
          focus: SelectionPoint(blockId: 'a', offset: 5),
        ),
      );
      final ops = EditorEditingOperations(ctrl);

      ops.applyAttributes(const InlineAttributes(color: '#ff0000'));

      final node = ctrl.document.findById('a')!;
      final op = node.delta!.ops.first as TextOp;
      expect(op.attributes.color, '#ff0000');
    });

    test('does nothing when selection is collapsed', () {
      final ctrl = _ctrl([_para('a', 'hello')]);
      ctrl.collapseSelection('a', 2);
      final ops = EditorEditingOperations(ctrl);

      ops.applyAttributes(const InlineAttributes(bold: true));

      final node = ctrl.document.findById('a')!;
      final op = node.delta!.ops.first as TextOp;
      expect(op.attributes.bold, isNull);
    });
  });

  group('FormattingToolbar — mixed attribute state', () {
    testWidgets('mixed bold block renders without error', (tester) async {
      final ctrl = _ctrl([_mixed('a')]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BlockEditorWidget(controller: ctrl)),
        ),
      );

      ctrl.updateSelection(
        const ExpandedSelection(
          anchor: SelectionPoint(blockId: 'a', offset: 0),
          focus: SelectionPoint(blockId: 'a', offset: 11),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(FormattingToolbar), findsOneWidget);
    });
  });

  group('FormattingToolbar — onColorPickerRequested callback', () {
    testWidgets('custom callback is invoked when text color button is tapped', (
      tester,
    ) async {
      var callbackInvoked = false;
      final ctrl = _ctrl([_para('a', 'hello')]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockEditorWidget(
              controller: ctrl,
              onColorPickerRequested: (current) async {
                callbackInvoked = true;
                return null;
              },
            ),
          ),
        ),
      );

      _expand(ctrl, 'a', 0, 5);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.format_color_text));
      await tester.pump();
      await tester.pump(Duration.zero);

      expect(callbackInvoked, isTrue);
    });

    testWidgets('returned Color is stored as hex string on the selection', (
      tester,
    ) async {
      const pickedColor = Color(0xFFFF0000);
      final ctrl = _ctrl([_para('a', 'hello')]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockEditorWidget(
              controller: ctrl,
              onColorPickerRequested: (_) async => pickedColor,
            ),
          ),
        ),
      );

      _expand(ctrl, 'a', 0, 5);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.format_color_text));
      await tester.pump();
      await tester.pump(Duration.zero);

      final node = ctrl.document.findById('a')!;
      final op = node.delta!.ops.first as TextOp;
      expect(op.attributes.color, '#ff0000');
    });

    testWidgets('null return from callback leaves selection unchanged', (
      tester,
    ) async {
      final ctrl = _ctrl([_para('a', 'hello')]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockEditorWidget(
              controller: ctrl,
              onColorPickerRequested: (_) async => null,
            ),
          ),
        ),
      );

      _expand(ctrl, 'a', 0, 5);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.format_color_text));
      await tester.pump();
      await tester.pump(Duration.zero);

      final node = ctrl.document.findById('a')!;
      final op = node.delta!.ops.first as TextOp;
      expect(op.attributes.color, isNull);
    });
  });
}

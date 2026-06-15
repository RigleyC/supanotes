import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/domain/note_editor_commands.dart';

DocumentSelection caretSelection(String nodeId) {
  return DocumentSelection.collapsed(
    position: DocumentPosition(
      nodeId: nodeId,
      nodePosition: TextNodePosition(offset: 0),
    ),
  );
}

DocumentSelection rangeSelection(String startId, String endId) {
  return DocumentSelection(
    base: DocumentPosition(
      nodeId: startId,
      nodePosition: TextNodePosition(offset: 0),
    ),
    extent: DocumentPosition(
      nodeId: endId,
      nodePosition: TextNodePosition(offset: 0),
    ),
  );
}

void main() {
  group('selectedNodes', () {
    test('returns the node at caret for collapsed selection', () {
      final document = MutableDocument(
        nodes: [
          ParagraphNode(id: 'node-1', text: AttributedText('Hello')),
        ],
      );
      final selection = caretSelection('node-1');

      final nodes = NoteEditorCommands.selectedNodes(document, selection);

      expect(nodes, hasLength(1));
      expect(nodes.first.id, 'node-1');
    });

    test('returns all nodes in range for expanded selection', () {
      final document = MutableDocument(
        nodes: [
          ParagraphNode(id: 'node-1', text: AttributedText('First')),
          ParagraphNode(id: 'node-2', text: AttributedText('Second')),
          ParagraphNode(id: 'node-3', text: AttributedText('Third')),
        ],
      );
      final selection = rangeSelection('node-1', 'node-3');

      final nodes = NoteEditorCommands.selectedNodes(document, selection);

      expect(nodes, hasLength(3));
      expect(nodes.map((n) => n.id), ['node-1', 'node-2', 'node-3']);
    });
  });

  group('toggleInlineAttribution', () {
    test('toggles bold on selection', () {
      final document = MutableDocument(
        nodes: [
          ParagraphNode(id: 'node-1', text: AttributedText('Hello world')),
        ],
      );
      final composer = MutableDocumentComposer(
        initialSelection: DocumentSelection(
          base: DocumentPosition(
            nodeId: 'node-1',
            nodePosition: TextNodePosition(offset: 0),
          ),
          extent: DocumentPosition(
            nodeId: 'node-1',
            nodePosition: TextNodePosition(offset: 5),
          ),
        ),
      );
      final editor = createDefaultDocumentEditor(
        document: document,
        composer: composer,
      );

      NoteEditorCommands.toggleInlineAttribution(editor, composer, boldAttribution);

      final node = document.first as TextNode;
      final spans = node.text.getAttributionSpansInRange(
        attributionFilter: (a) => a == boldAttribution,
        range: SpanRange(0, 5),
      );
      expect(spans, isNotEmpty);
    });
  });

  group('setBlockType', () {
    test('converts paragraph to H1', () {
      final document = MutableDocument(
        nodes: [
          ParagraphNode(id: 'node-1', text: AttributedText('Heading')),
        ],
      );
      final composer = MutableDocumentComposer(
        initialSelection: caretSelection('node-1'),
      );
      final editor = createDefaultDocumentEditor(
        document: document,
        composer: composer,
      );

      NoteEditorCommands.setBlockType(editor, composer, header1Attribution);

      expect(document.first, isA<ParagraphNode>());
      final para = document.first as ParagraphNode;
      expect(para.getMetadataValue('blockType'), header1Attribution);
    });

    test('converts task to H2', () {
      final document = MutableDocument(
        nodes: [
          TaskNode(
            id: 'node-1',
            text: AttributedText('Task heading'),
            isComplete: false,
          ),
        ],
      );
      final composer = MutableDocumentComposer(
        initialSelection: caretSelection('node-1'),
      );
      final editor = createDefaultDocumentEditor(
        document: document,
        composer: composer,
      );

      NoteEditorCommands.setBlockType(editor, composer, header2Attribution);

      expect(document.first, isA<ParagraphNode>());
      final para = document.first as ParagraphNode;
      expect(para.getMetadataValue('blockType'), header2Attribution);
    });

    test('converts list item to blockquote', () {
      final document = MutableDocument(
        nodes: [
          ListItemNode.unordered(
            id: 'node-1',
            text: AttributedText('List item'),
          ),
        ],
      );
      final composer = MutableDocumentComposer(
        initialSelection: caretSelection('node-1'),
      );
      final editor = createDefaultDocumentEditor(
        document: document,
        composer: composer,
      );

      NoteEditorCommands.setBlockType(editor, composer, blockquoteAttribution);

      expect(document.first, isA<ParagraphNode>());
      final para = document.first as ParagraphNode;
      expect(para.getMetadataValue('blockType'), blockquoteAttribution);
    });
  });

  group('convertToListItem', () {
    test('converts paragraph to unordered list', () {
      final document = MutableDocument(
        nodes: [
          ParagraphNode(id: 'node-1', text: AttributedText('Item')),
        ],
      );
      final composer = MutableDocumentComposer(
        initialSelection: caretSelection('node-1'),
      );
      final editor = createDefaultDocumentEditor(
        document: document,
        composer: composer,
      );

      NoteEditorCommands.convertToListItem(editor, composer, ListItemType.unordered);

      expect(document.first, isA<ListItemNode>());
      expect((document.first as ListItemNode).type, ListItemType.unordered);
    });

    test('converts task to ordered list', () {
      final document = MutableDocument(
        nodes: [
          TaskNode(
            id: 'node-1',
            text: AttributedText('Task item'),
            isComplete: false,
          ),
        ],
      );
      final composer = MutableDocumentComposer(
        initialSelection: caretSelection('node-1'),
      );
      final editor = createDefaultDocumentEditor(
        document: document,
        composer: composer,
      );

      NoteEditorCommands.convertToListItem(editor, composer, ListItemType.ordered);

      expect(document.first, isA<ListItemNode>());
      expect((document.first as ListItemNode).type, ListItemType.ordered);
    });

    test('changes unordered to ordered when already list', () {
      final document = MutableDocument(
        nodes: [
          ListItemNode.unordered(
            id: 'node-1',
            text: AttributedText('List item'),
          ),
        ],
      );
      final composer = MutableDocumentComposer(
        initialSelection: caretSelection('node-1'),
      );
      final editor = createDefaultDocumentEditor(
        document: document,
        composer: composer,
      );

      NoteEditorCommands.convertToListItem(editor, composer, ListItemType.ordered);

      expect(document.first, isA<ListItemNode>());
      expect((document.first as ListItemNode).type, ListItemType.ordered);
    });
  });

  group('convertToTask', () {
    test('converts paragraph to task', () {
      final document = MutableDocument(
        nodes: [
          ParagraphNode(id: 'node-1', text: AttributedText('Buy milk')),
        ],
      );
      final composer = MutableDocumentComposer(
        initialSelection: caretSelection('node-1'),
      );
      final editor = createDefaultDocumentEditor(
        document: document,
        composer: composer,
      );

      NoteEditorCommands.convertToTask(editor, composer);

      expect(document.first, isA<TaskNode>());
      expect((document.first as TaskNode).text.toPlainText(), 'Buy milk');
    });

    test('converts list item to task', () {
      final document = MutableDocument(
        nodes: [
          ListItemNode.unordered(
            id: 'node-1',
            text: AttributedText('Buy milk'),
          ),
        ],
      );
      final composer = MutableDocumentComposer(
        initialSelection: caretSelection('node-1'),
      );
      final editor = createDefaultDocumentEditor(
        document: document,
        composer: composer,
      );

      NoteEditorCommands.convertToTask(editor, composer);

      expect(document.first, isA<TaskNode>());
      expect((document.first as TaskNode).text.toPlainText(), 'Buy milk');
    });

    test('converts task back to paragraph', () {
      final document = MutableDocument(
        nodes: [
          TaskNode(
            id: 'node-1',
            text: AttributedText('Buy milk'),
            isComplete: false,
          ),
        ],
      );
      final composer = MutableDocumentComposer(
        initialSelection: caretSelection('node-1'),
      );
      final editor = createDefaultDocumentEditor(
        document: document,
        composer: composer,
      );

      NoteEditorCommands.convertToTask(editor, composer);

      expect(document.first, isA<ParagraphNode>());
      expect((document.first as ParagraphNode).text.toPlainText(), 'Buy milk');
    });
  });

  group('indentListItems', () {
    test('indents a list item', () {
      final document = MutableDocument(
        nodes: [
          ListItemNode.unordered(
            id: 'node-1',
            text: AttributedText('Item'),
          ),
        ],
      );
      final composer = MutableDocumentComposer(
        initialSelection: caretSelection('node-1'),
      );
      final editor = createDefaultDocumentEditor(
        document: document,
        composer: composer,
      );

      NoteEditorCommands.indentListItems(editor, composer);

      final item = document.first as ListItemNode;
      expect(item.indent, 1);
    });
  });

  group('unindentListItems', () {
    test('unindents a list item', () {
      final document = MutableDocument(
        nodes: [
          ListItemNode.unordered(
            id: 'node-1',
            text: AttributedText('Item'),
            indent: 2,
          ),
        ],
      );
      final composer = MutableDocumentComposer(
        initialSelection: caretSelection('node-1'),
      );
      final editor = createDefaultDocumentEditor(
        document: document,
        composer: composer,
      );

      NoteEditorCommands.unindentListItems(editor, composer);

      final item = document.first as ListItemNode;
      expect(item.indent, 1);
    });
  });
}

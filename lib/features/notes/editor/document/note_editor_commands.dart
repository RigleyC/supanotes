import 'dart:math' as math;

import 'package:supanotes/features/notes/editor/presentation/widgets/note_toolbar.dart' show NoteToolbar;
import 'package:super_editor/super_editor.dart';

/// Pure document-editing helpers used by [NoteToolbar].
class NoteEditorCommands {
  const NoteEditorCommands();

  /// Returns the selected nodes, or just the node at the caret if collapsed.
  static List<DocumentNode> selectedNodes(
    Document document,
    DocumentSelection? selection,
  ) {
    if (selection == null) return [];
    if (selection.isCollapsed) {
      final node = document.getNodeById(selection.extent.nodeId);
      return node != null ? [node] : [];
    }
    return document.getNodesInside(selection.start, selection.end).toList();
  }

  /// Toggles [attribution] across the current selection.
  static void toggleInlineAttribution(
    Editor editor,
    DocumentComposer composer,
    Attribution attribution,
  ) {
    final selection = composer.selection;
    if (selection == null) return;
    final range = selection.isCollapsed
        ? DocumentRange(start: selection.extent, end: selection.extent)
        : selection;
    editor.execute([
      ToggleTextAttributionsRequest(
        documentRange: range,
        attributions: {attribution},
      ),
    ]);
  }

  /// Changes block type of all selected nodes. Toggles off (back to paragraph)
  /// when the node already has the given [blockType].
  static void setBlockType(
    Editor editor,
    DocumentComposer composer,
    Attribution? blockType,
  ) {
    final nodes = _selectedEditableNodes(
      editor.context.document,
      composer.selection,
    );
    if (nodes.isEmpty) return;
    final targetBlockType = _targetBlockType(nodes, blockType);
    final requests = _buildBlockTypeRequests(nodes, targetBlockType);
    if (requests.isNotEmpty) editor.execute(requests);
  }

  static Attribution? _targetBlockType(
    List<DocumentNode> nodes,
    Attribution? blockType,
  ) {
    if (blockType == null) return null;
    final shouldClear = nodes.every(
      (node) =>
          node is ParagraphNode &&
          node.getMetadataValue('blockType') == blockType,
    );
    return shouldClear ? null : blockType;
  }

  static List<EditRequest> _buildBlockTypeRequests(
    List<DocumentNode> nodes,
    Attribution? blockType,
  ) {
    final requests = <EditRequest>[];
    for (final node in nodes) {
      requests.addAll(_requestsForBlockType(node, blockType));
    }
    return requests;
  }

  static List<EditRequest> _requestsForBlockType(
    DocumentNode node,
    Attribution? blockType,
  ) {
    if (node is ParagraphNode) {
      return [
        ChangeParagraphBlockTypeRequest(nodeId: node.id, blockType: blockType),
      ];
    }
    if (node is ListItemNode) {
      return [
        ConvertListItemToParagraphRequest(
          nodeId: node.id,
          paragraphMetadata: _blockTypeMetadata(blockType),
        ),
      ];
    }
    if (node is TaskNode) {
      return [
        ReplaceNodeRequest(
          existingNodeId: node.id,
          newNode: ParagraphNode(
            id: node.id,
            text: node.text,
            metadata: _blockTypeMetadata(blockType),
          ),
        ),
      ];
    }
    return const [];
  }

  static Map<String, dynamic> _blockTypeMetadata(Attribution? blockType) {
    return blockType == null ? const {} : {'blockType': blockType};
  }

  /// Converts selected nodes to the given list type. Toggles off (back to
  /// paragraph) when the node is already a list item of the same [type].
  static void convertToListItem(
    Editor editor,
    DocumentComposer composer,
    ListItemType type,
  ) {
    final nodes = _selectedEditableNodes(
      editor.context.document,
      composer.selection,
    );
    if (nodes.isEmpty) return;
    final shouldClear = nodes.every(
      (node) => node is ListItemNode && node.type == type,
    );
    final requests = <EditRequest>[];
    for (final node in nodes) {
      if (node is ListItemNode) {
        if (shouldClear) {
          requests.add(ConvertListItemToParagraphRequest(nodeId: node.id));
        } else {
          requests.add(
            ChangeListItemTypeRequest(nodeId: node.id, newType: type),
          );
        }
      } else if (node is TaskNode) {
        requests.add(
          ReplaceNodeRequest(
            existingNodeId: node.id,
            newNode: ListItemNode(
              id: node.id,
              itemType: type,
              text: node.text,
              indent: node.indent,
            ),
          ),
        );
      } else if (node is ParagraphNode) {
        requests.add(
          ConvertParagraphToListItemRequest(nodeId: node.id, type: type),
        );
      }
    }
    if (requests.isNotEmpty) editor.execute(requests);
  }

  /// Converts selected nodes to/from tasks.
  static void convertToTask(Editor editor, DocumentComposer composer) {
    final nodes = _selectedEditableNodes(
      editor.context.document,
      composer.selection,
    );
    if (nodes.isEmpty) return;
    final shouldClear = nodes.every((node) => node is TaskNode);
    final requests = <EditRequest>[];
    for (final node in nodes) {
      if (node is ParagraphNode) {
        requests.add(
          ReplaceNodeRequest(
            existingNodeId: node.id,
            newNode: TaskNode(
              id: node.id,
              text: node.text,
              isComplete: false,
              indent: node.indent,
              metadata: Map<String, dynamic>.from(node.metadata),
            ),
          ),
        );
      } else if (node is ListItemNode) {
        requests.add(
          ReplaceNodeRequest(
            existingNodeId: node.id,
            newNode: TaskNode(
              id: node.id,
              text: node.text,
              isComplete: false,
              indent: node.indent,
              metadata: Map<String, dynamic>.from(node.metadata),
            ),
          ),
        );
      } else if (node is TaskNode) {
        if (shouldClear) {
          requests.add(ConvertTaskToParagraphRequest(nodeId: node.id));
        }
      }
    }
    if (requests.isNotEmpty) editor.execute(requests);
  }

  /// Indents all selected list items and tasks.
  static void indentSelectedBlocks(Editor editor, DocumentComposer composer) {
    final requests = _selectedEditableNodes(
      editor.context.document,
      composer.selection,
    ).map(_indentRequestFor).whereType<EditRequest>().toList();
    if (requests.isNotEmpty) editor.execute(requests);
  }

  /// Unindents all selected list items and tasks.
  static void unindentSelectedBlocks(Editor editor, DocumentComposer composer) {
    final requests = _selectedEditableNodes(
      editor.context.document,
      composer.selection,
    ).map(_unindentRequestFor).whereType<EditRequest>().toList();
    if (requests.isNotEmpty) editor.execute(requests);
  }

  static EditRequest? _indentRequestFor(DocumentNode node) {
    if (node is ListItemNode) {
      return IndentListItemRequest(nodeId: node.id);
    }
    if (node is TaskNode) {
      return IndentTaskRequest(node.id);
    }
    return null;
  }

  static EditRequest? _unindentRequestFor(DocumentNode node) {
    if (node is ListItemNode) {
      return UnIndentListItemRequest(nodeId: node.id);
    }
    if (node is TaskNode) {
      return UnIndentTaskRequest(node.id);
    }
    return null;
  }

  /// Inserts an empty paragraph with [blockType] after the existing document.
  static void insertParagraphAtEnd(
    Editor editor, {
    required Attribution blockType,
  }) {
    insertNodeAtEnd(
      editor,
      ParagraphNode(
        id: Editor.createNodeId(),
        text: AttributedText(),
        metadata: {'blockType': blockType},
      ),
    );
  }

  /// Inserts an empty list item after the existing document.
  static void insertListItemAtEnd(Editor editor, {required ListItemType type}) {
    insertNodeAtEnd(
      editor,
      type == ListItemType.unordered
          ? ListItemNode.unordered(
              id: Editor.createNodeId(),
              text: AttributedText(),
            )
          : ListItemNode.ordered(
              id: Editor.createNodeId(),
              text: AttributedText(),
            ),
    );
  }

  /// Inserts an empty task after the existing document.
  static void insertTaskAtEnd(Editor editor) {
    insertNodeAtEnd(
      editor,
      TaskNode(
        id: Editor.createNodeId(),
        text: AttributedText(),
        isComplete: false,
      ),
    );
  }

  /// Inserts a node at the end and places the caret in it.
  static void insertNodeAtEnd(Editor editor, DocumentNode node) {
    final selection = DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: node.id,
        nodePosition: const TextNodePosition(offset: 0),
      ),
    );
    editor.execute([
      InsertNodeAtEndOfDocumentRequest(node),
      ChangeSelectionRequest(
        selection,
        SelectionChangeType.placeCaret,
        SelectionReason.contentChange,
      ),
    ]);
  }

  /// Inserts a divider followed by an empty paragraph at the document end.
  static void insertDividerAtEnd(Editor editor, {required int dividerCount}) {
    final paragraph = ParagraphNode(
      id: Editor.createNodeId(),
      text: AttributedText(),
    );
    final dividerIndex = math.Random().nextInt(dividerCount) + 1;
    editor.execute([
      InsertNodeAtEndOfDocumentRequest(
        HorizontalRuleNode(
          id: Editor.createNodeId(),
          metadata: {'dividerIndex': dividerIndex},
        ),
      ),
      InsertNodeAtEndOfDocumentRequest(paragraph),
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: paragraph.id,
            nodePosition: const TextNodePosition(offset: 0),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.contentChange,
      ),
    ]);
  }

  static List<DocumentNode> _selectedEditableNodes(
    Document document,
    DocumentSelection? selection,
  ) => selectedNodes(document, selection)
      .where(
        (node) =>
            node is ParagraphNode || node is ListItemNode || node is TaskNode,
      )
      .toList();

  /// Inserts a horizontal rule at the caret.
  static void insertDivider(Editor editor, {required int dividerCount}) {
    final index = math.Random().nextInt(dividerCount) + 1;
    editor.execute([
      InsertNodeAtCaretRequest(
        node: HorizontalRuleNode(
          id: Editor.createNodeId(),
          metadata: {'dividerIndex': index},
        ),
      ),
    ]);
  }
}

class RandomDividerConversionReaction extends EditReaction {

  const RandomDividerConversionReaction({this.dividerCount = 35});
  static final _hrPattern = RegExp(r'^(---|—-)\s');

  final int dividerCount;

  @override
  void react(
    EditContext editorContext,
    RequestDispatcher requestDispatcher,
    List<EditEvent> changeList,
  ) {
    if (changeList.length < 2) return;

    final document = editorContext.document;

    final didTypeSpace = EditInspector.didTypeSpace(document, changeList);
    if (!didTypeSpace) return;

    final edit =
        changeList.reversed.firstWhere((edit) => edit is DocumentEdit)
            as DocumentEdit;
    if (edit.change is! TextInsertionEvent) return;

    final textInsertionEvent = edit.change as TextInsertionEvent;
    final node = document.getNodeById(textInsertionEvent.nodeId);
    if (node is! TextNode) return;
    final match = _hrPattern.firstMatch(node.text.toPlainText())?.group(0);
    if (match == null) return;

    final index = math.Random().nextInt(dividerCount) + 1;

    requestDispatcher.execute([
      DeleteContentRequest(
        documentRange: DocumentRange(
          start: DocumentPosition(
            nodeId: node.id,
            nodePosition: const TextNodePosition(offset: 0),
          ),
          end: DocumentPosition(
            nodeId: node.id,
            nodePosition: TextNodePosition(offset: match.length),
          ),
        ),
      ),
      InsertNodeAtIndexRequest(
        nodeIndex: document.getNodeIndexById(node.id),
        newNode: HorizontalRuleNode(
          id: Editor.createNodeId(),
          metadata: {'dividerIndex': index},
        ),
      ),
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: node.id,
            nodePosition: const TextNodePosition(offset: 0),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.contentChange,
      ),
    ]);
  }
}

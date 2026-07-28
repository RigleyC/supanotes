import 'dart:math' as math;

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
    final shouldClear =
        blockType != null &&
        nodes.every(
          (node) =>
              node is ParagraphNode &&
              node.getMetadataValue('blockType') == blockType,
        );
    final targetBlockType = shouldClear ? null : blockType;
    final requests = <EditRequest>[];
    for (final node in nodes) {
      if (node is ParagraphNode) {
        requests.add(
          ChangeParagraphBlockTypeRequest(
            nodeId: node.id,
            blockType: targetBlockType,
          ),
        );
      } else if (node is ListItemNode) {
        requests.add(
          ConvertListItemToParagraphRequest(
            nodeId: node.id,
            paragraphMetadata: targetBlockType != null
                ? {'blockType': targetBlockType}
                : <String, dynamic>{},
          ),
        );
      } else if (node is TaskNode) {
        requests.add(
          ReplaceNodeRequest(
            existingNodeId: node.id,
            newNode: ParagraphNode(
              id: node.id,
              text: node.text,
              metadata: targetBlockType != null
                  ? {'blockType': targetBlockType}
                  : <String, dynamic>{},
            ),
          ),
        );
      }
    }
    if (requests.isNotEmpty) editor.execute(requests);
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
        requests.add(ConvertParagraphToTaskRequest(nodeId: node.id));
      } else if (node is ListItemNode) {
        requests.add(ConvertListItemToParagraphRequest(nodeId: node.id));
        requests.add(ConvertParagraphToTaskRequest(nodeId: node.id));
      } else if (node is TaskNode) {
        if (shouldClear) {
          requests.add(ConvertTaskToParagraphRequest(nodeId: node.id));
        }
      }
    }
    if (requests.isNotEmpty) editor.execute(requests);
  }

  /// Indents all selected list items.
  static void indentListItems(Editor editor, DocumentComposer composer) {
    final requests =
        _selectedEditableNodes(editor.context.document, composer.selection)
            .whereType<ListItemNode>()
            .map((node) => IndentListItemRequest(nodeId: node.id));
    final requestList = requests.toList();
    if (requestList.isNotEmpty) editor.execute(requestList);
  }

  /// Unindents all selected list items.
  static void unindentListItems(Editor editor, DocumentComposer composer) {
    final requests =
        _selectedEditableNodes(editor.context.document, composer.selection)
            .whereType<ListItemNode>()
            .map((node) => UnIndentListItemRequest(nodeId: node.id));
    final requestList = requests.toList();
    if (requestList.isNotEmpty) editor.execute(requestList);
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

  /// Converts a paragraph that contains only "---" into a horizontal rule.
  static bool convertDividerShortcut(
    Editor editor,
    DocumentComposer composer, {
    required int dividerCount,
  }) {
    final selection = composer.selection;
    if (selection == null || !selection.isCollapsed) return false;

    final document = editor.context.document;
    final node = document.getNodeById(selection.extent.nodeId);
    if (node is! ParagraphNode) return false;
    if (node.text.toPlainText() != '---') return false;

    final index = math.Random().nextInt(dividerCount) + 1;
    final paragraphAfter = ParagraphNode(
      id: Editor.createNodeId(),
      text: AttributedText(''),
    );

    editor.execute([
      ReplaceNodeRequest(
        existingNodeId: node.id,
        newNode: HorizontalRuleNode(
          id: node.id,
          metadata: {'dividerIndex': index},
        ),
      ),
      InsertNodeAtIndexRequest(
        nodeIndex: document.getNodeIndexById(node.id) + 1,
        newNode: paragraphAfter,
      ),
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: paragraphAfter.id,
            nodePosition: const TextNodePosition(offset: 0),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.contentChange,
      ),
    ]);
    return true;
  }
}

class RandomDividerConversionReaction extends EditReaction {
  static final _hrPattern = RegExp(r'^(---|—-)\s');

  const RandomDividerConversionReaction({this.dividerCount = 35});

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

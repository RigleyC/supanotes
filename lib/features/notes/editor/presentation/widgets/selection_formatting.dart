import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/editor/document/note_editor_commands.dart';

List<DocumentNode> editorSelectionNodes(
  Document document,
  DocumentSelection? selection,
) {
  if (selection == null ||
      document.getNodeById(selection.start.nodeId) == null ||
      document.getNodeById(selection.end.nodeId) == null) {
    return const [];
  }
  return NoteEditorCommands.selectedNodes(document, selection);
}

bool isEditorSelectionValid(Document document, DocumentSelection selection) {
  return document.getNodeById(selection.start.nodeId) != null &&
      document.getNodeById(selection.end.nodeId) != null;
}

bool hasAttributionInEditorSelection(
  Document document,
  DocumentSelection? selection,
  Attribution attribution,
) {
  if (selection == null || selection.isCollapsed) return false;

  var containsText = false;
  for (final node in editorSelectionNodes(
    document,
    selection,
  ).whereType<TextNode>()) {
    final startPosition = selection.start.nodeId == node.id
        ? selection.start.nodePosition
        : null;
    final endPosition = selection.end.nodeId == node.id
        ? selection.end.nodePosition
        : null;
    final start = startPosition is TextNodePosition ? startPosition.offset : 0;
    final end = endPosition is TextNodePosition
        ? endPosition.offset
        : node.text.length;
    final safeStart = start.clamp(0, node.text.length);
    final safeEnd = end.clamp(safeStart, node.text.length);
    for (var index = safeStart; index < safeEnd; index++) {
      containsText = true;
      if (!node.text.hasAttributionAt(index, attribution: attribution)) {
        return false;
      }
    }
  }
  return containsText;
}

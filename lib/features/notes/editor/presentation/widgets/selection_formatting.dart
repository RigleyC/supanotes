import 'package:supanotes/features/notes/editor/document/note_editor_commands.dart';
import 'package:super_editor/super_editor.dart';

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
    final range = _selectedTextRange(node, selection);
    containsText = containsText || range.start < range.end;
    if (!_hasAttributionInRange(node, range, attribution)) return false;
  }
  return containsText;
}

({int start, int end}) _selectedTextRange(
  TextNode node,
  DocumentSelection selection,
) {
  final start = _selectionOffset(
    position: selection.start,
    nodeId: node.id,
    fallback: 0,
  );
  final end = _selectionOffset(
    position: selection.end,
    nodeId: node.id,
    fallback: node.text.length,
  );
  final safeStart = start.clamp(0, node.text.length);
  final safeEnd = end.clamp(safeStart, node.text.length);
  return (start: safeStart, end: safeEnd);
}

int _selectionOffset({
  required DocumentPosition position,
  required String nodeId,
  required int fallback,
}) {
  if (position.nodeId != nodeId) return fallback;
  final nodePosition = position.nodePosition;
  return nodePosition is TextNodePosition ? nodePosition.offset : fallback;
}

bool _hasAttributionInRange(
  TextNode node,
  ({int start, int end}) range,
  Attribution attribution,
) {
  for (var index = range.start; index < range.end; index++) {
    if (!node.text.hasAttributionAt(index, attribution: attribution)) {
      return false;
    }
  }
  return true;
}

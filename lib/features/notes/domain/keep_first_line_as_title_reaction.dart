import 'package:super_editor/super_editor.dart';

final Set<String> _titlePromotionDismissedFor = {};

void markTitlePromotionDismissed(String nodeId) {
  _titlePromotionDismissedFor.add(nodeId);
}

void clearTitlePromotionDismissed(String nodeId) {
  _titlePromotionDismissedFor.remove(nodeId);
}

class KeepFirstLineAsTitleReaction extends EditReaction {
  const KeepFirstLineAsTitleReaction();

  @override
  void react(
    EditContext editorContext,
    RequestDispatcher requestDispatcher,
    List<EditEvent> changeList,
  ) {
    final document = editorContext.document;
    if (document.isEmpty) return;

    final firstNode = document.first;
    if (firstNode is ParagraphNode) {
      if (_titlePromotionDismissedFor.contains(firstNode.id)) return;
      if (firstNode.text.toPlainText().trim().isEmpty) return;
      final blockType = firstNode.getMetadataValue('blockType');
      if (blockType != header1Attribution) {
        requestDispatcher.execute([
          ChangeParagraphBlockTypeRequest(
            nodeId: firstNode.id,
            blockType: header1Attribution,
          ),
        ]);
      }
    }
  }
}

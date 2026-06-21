import 'package:super_editor/super_editor.dart';

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

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

    if (firstNode is! ParagraphNode) return;

    final hasHeaderBlockType = firstNode.getMetadataValue('blockType') != null;
    final text = firstNode.text.toPlainText();

    if (text.trim().isEmpty || hasHeaderBlockType) return;

    // Only promote on document edits (text insertion/deletion/formatting).
    final isDocumentEdit = changeList.any((event) => event is DocumentEdit);
    if (!isDocumentEdit) return;

    requestDispatcher.execute([
      ChangeParagraphBlockTypeRequest(
        nodeId: firstNode.id,
        blockType: header1Attribution,
      ),
    ]);
  }
}

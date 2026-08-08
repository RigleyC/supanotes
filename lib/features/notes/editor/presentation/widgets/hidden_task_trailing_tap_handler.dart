import 'package:flutter/rendering.dart';
import 'package:super_editor/super_editor.dart';

class HiddenTaskTrailingTapHandler extends ContentTapDelegate {
  HiddenTaskTrailingTapHandler({
    required this.editContext,
    required this.isHiddenTask,
    required this.openSoftwareKeyboard,
  });

  final SuperEditorContext editContext;
  final bool Function(TaskNode node) isHiddenTask;
  final void Function() openSoftwareKeyboard;

  @override
  TapHandlingInstruction onTap(DocumentTapDetails details) {
    final document = editContext.document;
    final nodes = document.toList();
    if (nodes.isEmpty) return TapHandlingInstruction.continueHandling;

    final layout = details.documentLayout;
    DocumentNode? lastVisibleNode;
    DocumentComponent? lastVisibleComponent;
    var hasHiddenTrailingTask = false;

    for (final node in nodes.reversed) {
      final component = layout.getComponentByNodeId(node.id);
      if (component?.isVisualSelectionSupported() == true) {
        lastVisibleNode = node;
        lastVisibleComponent = component;
        break;
      }
      if (node is! TaskNode || !isHiddenTask(node)) {
        return TapHandlingInstruction.continueHandling;
      }
      hasHiddenTrailingTask = true;
    }

    if (!hasHiddenTrailingTask) {
      return TapHandlingInstruction.continueHandling;
    }

    final requests = <EditRequest>[];
    if (lastVisibleNode is TextNode && lastVisibleComponent != null) {
      if (!_isTapBelowComponent(lastVisibleComponent, details.globalOffset)) {
        return TapHandlingInstruction.continueHandling;
      }
      requests.add(
        ChangeSelectionRequest(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: lastVisibleNode.id,
              nodePosition: lastVisibleComponent.getEndPosition(),
            ),
          ),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction,
        ),
      );
    } else {
      if (lastVisibleComponent != null &&
          !_isTapBelowComponent(lastVisibleComponent, details.globalOffset)) {
        return TapHandlingInstruction.continueHandling;
      }
      final newNodeId = Editor.createNodeId();
      requests.addAll([
        InsertNodeAfterNodeRequest(
          existingNodeId: nodes.last.id,
          newNode: ParagraphNode(id: newNodeId, text: AttributedText()),
        ),
        ChangeSelectionRequest(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: newNodeId,
              nodePosition: const TextNodePosition(offset: 0),
            ),
          ),
          SelectionChangeType.insertContent,
          SelectionReason.userInteraction,
        ),
      ]);
    }

    editContext.editor.execute([
      ...requests,
      const ClearComposingRegionRequest(),
    ]);
    editContext.editorFocusNode.requestFocus();
    openSoftwareKeyboard();

    return TapHandlingInstruction.halt;
  }

  bool _isTapBelowComponent(DocumentComponent component, Offset globalOffset) {
    final componentBox = component.context.findRenderObject() as RenderBox;
    final tapOffset = componentBox.globalToLocal(globalOffset);
    return tapOffset.dy > componentBox.size.height;
  }
}

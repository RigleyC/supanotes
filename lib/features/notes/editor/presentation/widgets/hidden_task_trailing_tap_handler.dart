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
    final region = _findTrailingHiddenTaskRegion(
      document,
      details.documentLayout,
    );
    if (region == null) {
      return TapHandlingInstruction.continueHandling;
    }

    final requests = _buildRequests(
      region: region,
      globalOffset: details.globalOffset,
    );
    if (requests == null) return TapHandlingInstruction.continueHandling;

    editContext.editor.execute([
      ...requests,
      const ClearComposingRegionRequest(),
    ]);
    editContext.editorFocusNode.requestFocus();
    openSoftwareKeyboard();

    return TapHandlingInstruction.halt;
  }

  _TrailingHiddenTaskRegion? _findTrailingHiddenTaskRegion(
    Document document,
    DocumentLayout layout,
  ) {
    final nodes = document.toList();
    if (nodes.isEmpty) return null;

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
        return null;
      }
      hasHiddenTrailingTask = true;
    }

    if (!hasHiddenTrailingTask) {
      return null;
    }
    return _TrailingHiddenTaskRegion(
      nodes: nodes,
      lastVisibleNode: lastVisibleNode,
      lastVisibleComponent: lastVisibleComponent,
    );
  }

  List<EditRequest>? _buildRequests({
    required _TrailingHiddenTaskRegion region,
    required Offset globalOffset,
  }) {
    final lastVisibleNode = region.lastVisibleNode;
    final lastVisibleComponent = region.lastVisibleComponent;
    if (lastVisibleNode is TextNode && lastVisibleComponent != null) {
      if (!_isTapBelowComponent(lastVisibleComponent, globalOffset)) {
        return null;
      }
      return [
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
      ];
    }

    if (lastVisibleComponent != null &&
        !_isTapBelowComponent(lastVisibleComponent, globalOffset)) {
      return null;
    }
    final newNodeId = Editor.createNodeId();
    return [
      InsertNodeAfterNodeRequest(
        existingNodeId: region.nodes.last.id,
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
    ];
  }

  bool _isTapBelowComponent(DocumentComponent component, Offset globalOffset) {
    final componentBox = component.context.findRenderObject()! as RenderBox;
    final tapOffset = componentBox.globalToLocal(globalOffset);
    return tapOffset.dy > componentBox.size.height;
  }
}

class _TrailingHiddenTaskRegion {
  const _TrailingHiddenTaskRegion({
    required this.nodes,
    required this.lastVisibleNode,
    required this.lastVisibleComponent,
  });

  final List<DocumentNode> nodes;
  final DocumentNode? lastVisibleNode;
  final DocumentComponent? lastVisibleComponent;
}

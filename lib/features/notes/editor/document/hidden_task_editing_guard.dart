import 'package:collection/collection.dart';
import 'package:super_editor/super_editor.dart';

/// Prevents hidden completed tasks from participating in document editing.
///
/// Hidden tasks remain in the canonical document because removing a node from
/// that document is a real document mutation. This guard only changes how
/// editor requests are handled while the presentation hides the task.
class HiddenTaskEditingGuard {
  HiddenTaskEditingGuard({bool Function(TaskNode node)? isHiddenTask})
    : _isHiddenTaskPredicate = isHiddenTask ?? _neverHidden;

  bool Function(TaskNode node) _isHiddenTaskPredicate;

  void updateHiddenTaskPredicate(bool Function(TaskNode node) predicate) {
    _isHiddenTaskPredicate = predicate;
  }

  EditCommand? handle(Editor editor, EditRequest request) {
    final document = editor.document;
    final composer = editor.context.find<MutableDocumentComposer>(
      Editor.composerKey,
    );
    final selection = composer.selection;

    if (request is ChangeSelectionRequest) {
      return _handleSelectionChange(document, request);
    }

    if (request is DeleteUpstreamRequest) {
      return _handleDirectionalDeletion(document, selection, upstream: true);
    }

    if (request is DeleteDownstreamRequest) {
      return _handleDirectionalDeletion(document, selection, upstream: false);
    }

    if (request is DeleteUpstreamAtBeginningOfNodeRequest) {
      return _handleNodeStartDeletion(document, request);
    }

    if (request is DeleteUpstreamCharacterRequest ||
        request is DeleteDownstreamCharacterRequest ||
        request is DeleteSelectionRequest) {
      return _handleCharacterDeletion(document, selection);
    }

    if (request is DeleteContentRequest) {
      return _handleDeleteContent(document, selection, request);
    }

    if (request is AddTextAttributionsRequest ||
        request is RemoveTextAttributionsRequest ||
        request is ToggleTextAttributionsRequest) {
      return _handleAttributionChange(
        document,
        selection,
        _attributionRange(request),
      );
    }

    if (request is InsertTextRequest ||
        request is InsertAttributedTextRequest) {
      return _handleTextInsertion(
        document,
        selection,
        _insertionPosition(request),
      );
    }

    if (_requestUsesCurrentSelection(request) &&
        selectionTouchesHiddenTask(document, selection)) {
      return _clearSelectionCommand();
    }

    if (_requestTargetsHiddenTask(document, request)) {
      return const _NoOpEditCommand();
    }

    return null;
  }

  EditCommand? _handleSelectionChange(
    Document document,
    ChangeSelectionRequest request,
  ) {
    final requestedSelection = request.newSelection;
    if (requestedSelection == null) {
      return null;
    }

    final selectedNodes = document.getNodesInside(
      requestedSelection.start,
      requestedSelection.end,
    );
    if (selectedNodes.isEmpty ||
        selectedNodes.any((node) => !_isHiddenTask(node))) {
      // Hidden tasks are barriers for editing, but they must not make a
      // whole-note selection disappear. The visible nodes in the range stay
      // selectable while destructive operations below preserve hidden tasks.
      return null;
    }

    return ChangeSelectionCommand(
      null,
      SelectionChangeType.clearSelection,
      request.reason,
      notifyListeners: request.notifyListeners,
    );
  }

  EditCommand? _handleDirectionalDeletion(
    Document document,
    DocumentSelection? selection, {
    required bool upstream,
  }) {
    if (selectionTouchesHiddenTask(document, selection)) {
      return _clearSelectionCommand();
    }
    if (_deleteWouldCrossHiddenTask(document, selection, upstream: upstream)) {
      final node = document.getNodeById(selection!.extent.nodeId);
      if (node == null) return const _NoOpEditCommand();
      if (upstream && node is ListItemNode) {
        // A list item at offset zero can be converted without crossing the
        // hidden task above it. This also covers IME paths that dispatch the
        // generic upstream deletion request.
        return ConvertListItemToParagraphCommand(
          nodeId: node.id,
          paragraphMetadata: node.metadata,
        );
      }
      final visibleNeighbor = upstream
          ? _visibleNodeBefore(document, node.id)
          : _visibleNodeAfter(document, node.id);
      if (visibleNeighbor == null) return const _NoOpEditCommand();
      return _moveCaretToBoundary(visibleNeighbor, upstream: upstream);
    }
    return null;
  }

  EditCommand? _handleNodeStartDeletion(
    Document document,
    DeleteUpstreamAtBeginningOfNodeRequest request,
  ) {
    if (_isHiddenTask(request.node)) {
      return const _NoOpEditCommand();
    }
    final previousNode = document.getNodeBeforeById(request.node.id);
    if (_isHiddenTask(previousNode)) {
      // Backspace on a list item only changes that item into a paragraph.
      // It does not cross the hidden task, so keep SuperEditor's normal list
      // editing behavior available below the hidden node.
      if (request.node is ListItemNode) return null;

      final visibleNode = _visibleNodeBefore(document, request.node.id);
      if (visibleNode == null) return const _NoOpEditCommand();
      return _moveCaretToBoundary(visibleNode, upstream: true);
    }
    return null;
  }

  EditCommand? _handleCharacterDeletion(
    Document document,
    DocumentSelection? selection,
  ) {
    if (!selectionTouchesHiddenTask(document, selection)) return null;
    if (selection == null || selection.isCollapsed) {
      return _clearSelectionCommand();
    }

    return _DeleteVisibleContentCommand(
      documentRange: selection,
      isHiddenTask: _isHiddenTask,
    );
  }

  EditCommand? _handleDeleteContent(
    Document document,
    DocumentSelection? selection,
    DeleteContentRequest request,
  ) {
    if (!_rangeTouchesHiddenTask(document, request.documentRange)) return null;

    final hasVisibleContent = document
        .getNodesInside(
          request.documentRange.start,
          request.documentRange.end,
        )
        .any((node) => !_isHiddenTask(node) && node.isDeletable);
    if (!hasVisibleContent) {
      return selectionTouchesHiddenTask(document, selection)
          ? _clearSelectionCommand()
          : const _NoOpEditCommand();
    }

    return _DeleteVisibleContentCommand(
      documentRange: request.documentRange,
      isHiddenTask: _isHiddenTask,
    );
  }

  EditCommand? _handleAttributionChange(
    Document document,
    DocumentSelection? selection,
    DocumentRange range,
  ) {
    if (!_rangeTouchesHiddenTask(document, range)) return null;
    return selectionTouchesHiddenTask(document, selection)
        ? _clearSelectionCommand()
        : const _NoOpEditCommand();
  }

  DocumentRange _attributionRange(EditRequest request) {
    return switch (request) {
      final AddTextAttributionsRequest request => request.documentRange,
      final RemoveTextAttributionsRequest request => request.documentRange,
      final ToggleTextAttributionsRequest request => request.documentRange,
      _ => throw StateError('Unsupported attribution request'),
    };
  }

  EditCommand? _handleTextInsertion(
    Document document,
    DocumentSelection? selection,
    DocumentPosition position,
  ) {
    if (!_isHiddenTask(document.getNodeById(position.nodeId))) return null;
    return selectionTouchesHiddenTask(document, selection)
        ? _clearSelectionCommand()
        : const _NoOpEditCommand();
  }

  DocumentPosition _insertionPosition(EditRequest request) {
    return switch (request) {
      final InsertTextRequest request => request.documentPosition,
      final InsertAttributedTextRequest request => request.documentPosition,
      _ => throw StateError('Unsupported text insertion request'),
    };
  }

  EditCommand _clearSelectionCommand() {
    return const ChangeSelectionCommand(
      null,
      SelectionChangeType.clearSelection,
      SelectionReason.contentChange,
    );
  }

  bool selectionTouchesHiddenTask(
    Document document,
    DocumentSelection? selection,
  ) {
    if (selection == null) return false;
    return _rangeTouchesHiddenTask(document, selection);
  }

  bool _rangeTouchesHiddenTask(Document document, DocumentRange range) {
    final startNode = document.getNodeById(range.start.nodeId);
    final endNode = document.getNodeById(range.end.nodeId);
    if (startNode == null || endNode == null) return false;

    return document.getNodesInside(range.start, range.end).any(_isHiddenTask);
  }

  bool _isHiddenTask(DocumentNode? node) {
    return node is TaskNode && _isHiddenTaskPredicate(node);
  }

  bool _deleteWouldCrossHiddenTask(
    Document document,
    DocumentSelection? selection, {
    required bool upstream,
  }) {
    if (selection == null || !selection.isCollapsed) return false;

    final node = document.getNodeById(selection.extent.nodeId);
    if (node is! TextNode ||
        selection.extent.nodePosition is! TextNodePosition) {
      return false;
    }

    final offset = (selection.extent.nodePosition as TextNodePosition).offset;
    final isAtBoundary = upstream ? offset == 0 : offset == node.text.length;
    if (!isAtBoundary) return false;

    final adjacentNode = upstream
        ? document.getNodeBeforeById(node.id)
        : document.getNodeAfterById(node.id);
    return _isHiddenTask(adjacentNode);
  }

  DocumentNode? _visibleNodeBefore(Document document, String nodeId) {
    var node = document.getNodeBeforeById(nodeId);
    while (node != null && _isHiddenTask(node)) {
      node = document.getNodeBeforeById(node.id);
    }
    return node;
  }

  DocumentNode? _visibleNodeAfter(Document document, String nodeId) {
    var node = document.getNodeAfterById(nodeId);
    while (node != null && _isHiddenTask(node)) {
      node = document.getNodeAfterById(node.id);
    }
    return node;
  }

  EditCommand _moveCaretToBoundary(
    DocumentNode node, {
    required bool upstream,
  }) {
    return ChangeSelectionCommand(
      DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: node.id,
          nodePosition: upstream ? node.endPosition : node.beginningPosition,
        ),
      ),
      SelectionChangeType.deleteContent,
      SelectionReason.userInteraction,
    );
  }

  bool _requestUsesCurrentSelection(EditRequest request) {
    return request is InsertPlainTextAtCaretRequest ||
        request is InsertStyledTextAtCaretRequest ||
        request is InsertInlinePlaceholderAtCaretRequest ||
        request is InsertCharacterAtCaretRequest ||
        request is InsertNewlineAtCaretRequest ||
        request is InsertSoftNewlineAtCaretRequest ||
        request is InsertNodeAtCaretRequest ||
        request is PasteEditorRequest ||
        request is PasteStructuredContentEditorRequest;
  }

  bool _requestTargetsHiddenTask(Document document, EditRequest request) {
    final nodeId = switch (request) {
      final ChangeParagraphAlignmentRequest request => request.nodeId,
      final ChangeParagraphBlockTypeRequest request => request.nodeId,
      final IndentParagraphRequest request => request.nodeId,
      final UnIndentParagraphRequest request => request.nodeId,
      final SetParagraphIndentRequest request => request.nodeId,
      final ConvertParagraphToTaskRequest request => request.nodeId,
      final ConvertTaskToParagraphRequest request => request.nodeId,
      final SplitExistingTaskRequest request => request.existingNodeId,
      final IndentTaskRequest request => request.nodeId,
      final UnIndentTaskRequest request => request.nodeId,
      final SetTaskIndentRequest request => request.nodeId,
      final ChangeListItemTypeRequest request => request.nodeId,
      final DeleteNodeRequest request => request.nodeId,
      _ => null,
    };

    return nodeId != null && _isHiddenTask(document.getNodeById(nodeId));
  }
}

/// Deletes selected visible content without allowing hidden tasks to be
/// removed or used to merge content across their boundary.
class _DeleteVisibleContentCommand extends EditCommand {
  const _DeleteVisibleContentCommand({
    required this.documentRange,
    required this.isHiddenTask,
  });

  final DocumentRange documentRange;
  final bool Function(DocumentNode node) isHiddenTask;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  String describe() => 'Delete visible content within range: $documentRange';

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final document = context.document;
    final normalizedRange = documentRange.normalize(document);
    final selectedNodes = document.getNodesInside(
      normalizedRange.start,
      normalizedRange.end,
    );
    final deletableVisibleNodes = selectedNodes
        .where((node) => !isHiddenTask(node) && node.isDeletable)
        .toList(growable: false);
    if (deletableVisibleNodes.isEmpty) return;

    final deletedNodeIds = <String>[];
    final partialCaretPositions = <String, DocumentPosition>{};

    // Work from downstream to upstream so removing a node never invalidates
    // the IDs and positions needed by the remaining selected nodes.
    for (var index = selectedNodes.length - 1; index >= 0; index -= 1) {
      final node = selectedNodes[index];
      if (isHiddenTask(node) || !node.isDeletable) continue;

      final startPosition = DocumentPosition(
        nodeId: node.id,
        nodePosition: index == 0
            ? normalizedRange.start.nodePosition
            : node.beginningPosition,
      );
      final endPosition = DocumentPosition(
        nodeId: node.id,
        nodePosition: index == selectedNodes.length - 1
            ? normalizedRange.end.nodePosition
            : node.endPosition,
      );
      final isFullySelected =
          startPosition.nodePosition.isEquivalentTo(node.beginningPosition) &&
          endPosition.nodePosition.isEquivalentTo(node.endPosition);

      if (isFullySelected) {
        executor.executeCommand(DeleteNodeCommand(nodeId: node.id));
        deletedNodeIds.add(node.id);
      } else {
        executor.executeCommand(
          DeleteContentCommand(
            documentRange: DocumentRange(
              start: startPosition,
              end: endPosition,
            ),
          ),
        );
        partialCaretPositions[node.id] = index == 0
            ? startPosition
            : DocumentPosition(
                nodeId: node.id,
                nodePosition: node.beginningPosition,
              );
      }
    }

    final remainingPartialCaret = selectedNodes
        .map((node) => partialCaretPositions[node.id])
        .whereType<DocumentPosition>()
        .map(
          (position) =>
              document.getNodeById(position.nodeId) == null ? null : position,
        )
        .whereType<DocumentPosition>()
        .firstOrNull;
    if (remainingPartialCaret != null) {
      executor.executeCommand(
        ChangeSelectionCommand(
          DocumentSelection.collapsed(
            position: remainingPartialCaret,
          ),
          SelectionChangeType.deleteContent,
          SelectionReason.userInteraction,
        ),
      );
    } else {
      final hiddenNodes = selectedNodes.where(isHiddenTask).toList();
      final hiddenAnchor = hiddenNodes.reversed
          .map((node) => document.getNodeById(node.id))
          .whereType<DocumentNode>()
          .firstOrNull;
      if (hiddenAnchor == null) return;

      final replacementId = deletedNodeIds.first;
      final emptyParagraph = ParagraphNode(
        id: replacementId,
        text: AttributedText(),
      );
      final insertIndex = document.getNodeIndexById(hiddenAnchor.id) + 1;
      document.insertNodeAt(insertIndex, emptyParagraph);
      executor.logChanges([
        DocumentEdit(NodeChangeEvent(emptyParagraph.id)),
      ]);
      executor.executeCommand(
        ChangeSelectionCommand(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: emptyParagraph.id,
              nodePosition: emptyParagraph.beginningPosition,
            ),
          ),
          SelectionChangeType.deleteContent,
          SelectionReason.userInteraction,
        ),
      );
    }

    executor.executeCommand(ChangeComposingRegionCommand(null));
  }
}

bool _neverHidden(TaskNode node) => false;

class _NoOpEditCommand extends EditCommand {
  const _NoOpEditCommand();

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.nonHistorical;

  @override
  void execute(EditContext context, CommandExecutor executor) {}
}

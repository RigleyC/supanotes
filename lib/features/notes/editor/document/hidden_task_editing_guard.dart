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
    if (requestedSelection == null ||
        !selectionTouchesHiddenTask(document, requestedSelection)) {
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
      return const _NoOpEditCommand();
    }
    return null;
  }

  EditCommand? _handleNodeStartDeletion(
    Document document,
    DeleteUpstreamAtBeginningOfNodeRequest request,
  ) {
    if (_isHiddenTask(request.node) ||
        _isHiddenTask(document.getNodeBeforeById(request.node.id))) {
      return const _NoOpEditCommand();
    }
    return null;
  }

  EditCommand? _handleCharacterDeletion(
    Document document,
    DocumentSelection? selection,
  ) {
    return selectionTouchesHiddenTask(document, selection)
        ? _clearSelectionCommand()
        : null;
  }

  EditCommand? _handleDeleteContent(
    Document document,
    DocumentSelection? selection,
    DeleteContentRequest request,
  ) {
    if (!_rangeTouchesHiddenTask(document, request.documentRange)) return null;
    return selectionTouchesHiddenTask(document, selection)
        ? _clearSelectionCommand()
        : const _NoOpEditCommand();
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
      AddTextAttributionsRequest request => request.documentRange,
      RemoveTextAttributionsRequest request => request.documentRange,
      ToggleTextAttributionsRequest request => request.documentRange,
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
      InsertTextRequest request => request.documentPosition,
      InsertAttributedTextRequest request => request.documentPosition,
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
      ChangeParagraphAlignmentRequest request => request.nodeId,
      ChangeParagraphBlockTypeRequest request => request.nodeId,
      IndentParagraphRequest request => request.nodeId,
      UnIndentParagraphRequest request => request.nodeId,
      SetParagraphIndentRequest request => request.nodeId,
      ConvertParagraphToTaskRequest request => request.nodeId,
      ConvertTaskToParagraphRequest request => request.nodeId,
      SplitExistingTaskRequest request => request.existingNodeId,
      IndentTaskRequest request => request.nodeId,
      UnIndentTaskRequest request => request.nodeId,
      SetTaskIndentRequest request => request.nodeId,
      ChangeListItemTypeRequest request => request.nodeId,
      _ => null,
    };

    return nodeId != null && _isHiddenTask(document.getNodeById(nodeId));
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

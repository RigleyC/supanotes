import 'package:super_editor/super_editor.dart';

/// Overrides SuperEditor's default empty-task backspace behavior.
///
/// SuperEditor converts a task to a paragraph when backspace is pressed at the
/// beginning of the task. For an empty task in a multi-block note, Supanotes
/// instead removes the task entirely and moves the caret to the nearest
/// remaining block. A single empty task still falls through to SuperEditor's
/// default conversion so the document keeps an editable paragraph.
EditCommand? handleEmptyTaskDeletion(Editor editor, EditRequest request) {
  if (request is! DeleteUpstreamAtBeginningOfNodeRequest ||
      request.node is! TaskNode) {
    return null;
  }

  final task = editor.document.getNodeById(request.node.id);
  if (task is! TaskNode || task.text.isNotEmpty || editor.document.nodeCount <= 1) {
    return null;
  }

  final previousNode = editor.document.getNodeBeforeById(task.id);
  final nextNode = editor.document.getNodeAfterById(task.id);
  final selectionTarget = previousNode ?? nextNode;
  if (selectionTarget == null) return null;

  return _DeleteEmptyTaskCommand(
    taskId: task.id,
    selectionPosition: DocumentPosition(
      nodeId: selectionTarget.id,
      nodePosition: previousNode != null
          ? selectionTarget.endPosition
          : selectionTarget.beginningPosition,
    ),
  );
}

class _DeleteEmptyTaskCommand extends EditCommand {
  const _DeleteEmptyTaskCommand({
    required this.taskId,
    required this.selectionPosition,
  });

  final String taskId;
  final DocumentPosition selectionPosition;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    executor
      ..executeCommand(DeleteNodeCommand(nodeId: taskId))
      ..executeCommand(
        ChangeSelectionCommand(
          DocumentSelection.collapsed(position: selectionPosition),
          SelectionChangeType.deleteContent,
          SelectionReason.userInteraction,
        ),
      );
  }
}

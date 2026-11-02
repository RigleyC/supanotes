import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_codec.dart';
import 'package:supanotes/features/notes/editor/document/note_task_editor_commands.dart';
import 'package:supanotes/features/tasks/domain/task_completion_command.dart';

/// Task actions on the AppFlowy document. Each one is a single local
/// transaction, so it syncs like typing and can be undone.
extension NoteTaskCommands on EditorState {
  /// The node whose stable block id is [blockId].
  Node? nodeForBlock(String blockId) {
    Node? search(Iterable<Node> nodes) {
      for (final node in nodes) {
        if (node.attributes[NoteNodeKeys.blockId] == blockId) return node;
        final found = search(node.children);
        if (found != null) return found;
      }
      return null;
    }

    return search(document.root.children);
  }

  /// Completes the current occurrence of task [blockId].
  Future<TaskCompletionResult?> completeNoteTask(
    String blockId, {
    NoteTaskEditorCommands commands = const NoteTaskEditorCommands(),
    DateTime? now,
    DateTime? scheduledAt,
  }) async {
    final node = _task(blockId);
    if (node == null) return null;
    final (state, result) = commands.completeState(
      _stateOf(node),
      now: now,
      scheduledAt: scheduledAt,
    );
    await _write(node, state);
    return result;
  }

  /// Reopens task [blockId], or only its occurrence at [scheduledAt].
  Future<void> reopenNoteTask(
    String blockId, {
    NoteTaskEditorCommands commands = const NoteTaskEditorCommands(),
    DateTime? previousDue,
    DateTime? scheduledAt,
  }) async {
    final node = _task(blockId);
    if (node == null) return;
    await _write(
      node,
      commands.reopenState(
        _stateOf(node),
        previousDue: previousDue,
        scheduledAt: scheduledAt,
      ),
    );
  }

  /// Changes the schedule or reminder of task [blockId].
  Future<void> updateNoteTaskMetadata(
    String blockId, {
    NoteTaskEditorCommands commands = const NoteTaskEditorCommands(),
    DateTime? dueDate,
    String? recurrence,
    bool clearDueDate = false,
    bool clearRecurrence = false,
    bool? hasTime,
    String? reminder,
    bool clearReminder = false,
  }) async {
    final node = _task(blockId);
    if (node == null) return;
    final state = commands.updateMetadataState(
      _stateOf(node),
      dueDate: dueDate,
      recurrence: recurrence,
      clearDueDate: clearDueDate,
      clearRecurrence: clearRecurrence,
      hasTime: hasTime,
      reminder: reminder,
      clearReminder: clearReminder,
    );
    if (state != null) await _write(node, state);
  }

  Node? _task(String blockId) {
    final node = nodeForBlock(blockId);
    return node?.type == TodoListBlockKeys.type ? node : null;
  }

  NoteTaskState _stateOf(Node node) => (
    isComplete: node.attributes[TodoListBlockKeys.checked] as bool? ?? false,
    metadata: Map<String, dynamic>.from(
      node.attributes[NoteNodeKeys.metadata] as Map? ?? const {},
    ),
  );

  Future<void> _write(Node node, NoteTaskState state) {
    final metadata = Map<String, dynamic>.from(state.metadata)
      ..remove('isCompleted')
      ..remove('indent');
    final transaction = this.transaction
      ..updateNode(node, {
        TodoListBlockKeys.checked: state.isComplete,
        NoteNodeKeys.metadata: metadata.isEmpty ? null : metadata,
      });
    return apply(transaction, withUpdateSelection: false);
  }
}

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:supanotes/features/notes/editor/appflowy/blocks/note_task_block.dart';

/// The note's editor state, aware of completed tasks the user hid.
///
/// Hidden tasks stay in the document (removing them would be a real edit
/// that syncs), but they are invisible, so the user must not edit them by
/// accident: a Backspace that would merge a line into a hidden task, a
/// selection that deletes across one, or a caret that lands inside one.
/// Every edit, from the keyboard, the IME, paste or a command, goes through
/// [apply], so that is where they are refused.
class NoteEditorState extends EditorState {
  /// Creates the state for [document].
  NoteEditorState({required super.document}) {
    selectionNotifier.addListener(_keepSelectionVisible);
  }

  bool _hideCompleted = false;

  /// Whether completed tasks are hidden from the note.
  bool get hideCompleted => _hideCompleted;
  set hideCompleted(bool value) {
    if (_hideCompleted == value) return;
    _hideCompleted = value;
    _keepSelectionVisible();
  }

  /// Whether [node] is a task the user cannot see right now.
  bool isHidden(Node node) =>
      _hideCompleted &&
      node.type == TodoListBlockKeys.type &&
      resolveTaskCompletion(node).isComplete;

  @override
  Future<void> apply(
    Transaction transaction, {
    bool isRemote = false,
    ApplyOptions options = const ApplyOptions(),
    bool withUpdateSelection = true,
    bool skipHistoryDebounce = false,
    bool skipEditableCheck = false,
  }) {
    if (!isRemote && _hideCompleted && _touchesHiddenContent(transaction)) {
      return Future.value();
    }
    return super.apply(
      transaction,
      isRemote: isRemote,
      options: options,
      withUpdateSelection: withUpdateSelection,
      skipHistoryDebounce: skipHistoryDebounce,
      skipEditableCheck: skipEditableCheck,
    );
  }

  /// True when [transaction] would change the text of a hidden task or
  /// delete one. Attribute updates (completing, reopening, rescheduling) are
  /// allowed: those are the task commands themselves.
  bool _touchesHiddenContent(Transaction transaction) {
    // Only the nodes the transaction touches are checked, so typing costs
    // the same however many tasks the note has.
    bool isHiddenNode(Node node) =>
        isHidden(node) || node.children.any(isHiddenNode);

    final operations = transaction.operations;
    for (var i = 0; i < operations.length; i++) {
      final operation = operations[i];
      final Path? textPath = switch (operation) {
        UpdateTextOperation(:final path) => path,
        UpdateOperation(:final path, :final attributes)
            when attributes.containsKey('delta') =>
          path,
        _ => null,
      };
      if (operation case DeleteOperation(:final nodes)) {
        // Deleted nodes are the document's own nodes: check them directly.
        if (nodes.any(isHiddenNode)) return true;
      } else if (textPath != null) {
        final original = _pathBefore(textPath, operations.take(i));
        final node = original == null ? null : getNodeAtPath(original);
        if (node != null && isHidden(node)) return true;
      }
    }
    return false;
  }

  /// Where [path], as seen after [earlier] operations ran, was in the
  /// document before the transaction; null for a node those operations
  /// inserted.
  static Path? _pathBefore(Path path, Iterable<Operation> earlier) {
    var result = [...path];
    for (final operation in earlier.toList().reversed) {
      final (Path at, int count, bool inserted) = switch (operation) {
        InsertOperation(:final path, :final nodes) => (
          path,
          nodes.length,
          true,
        ),
        DeleteOperation(:final path, :final nodes) => (
          path,
          nodes.length,
          false,
        ),
        _ => (const <int>[], 0, false),
      };
      if (at.isEmpty || count == 0) continue;
      final level = at.length - 1;
      if (result.length <= level) continue;
      var sameParent = true;
      for (var j = 0; j < level; j++) {
        if (result[j] != at[j]) {
          sameParent = false;
          break;
        }
      }
      if (!sameParent || result[level] < at[level]) continue;
      if (inserted) {
        if (result[level] < at[level] + count) return null;
        result = [...result]..[level] -= count;
      } else {
        result = [...result]..[level] += count;
      }
    }
    return result;
  }

  /// Moves a caret that ended up in a hidden task (arrow keys, a remote
  /// change, turning "hide completed" on) to the next visible text block.
  void _keepSelectionVisible() {
    if (!_hideCompleted) return;
    final current = selection;
    if (current == null) return;
    final node = getNodeAtPath(current.end.path);
    if (node == null || !isHidden(node)) return;
    final target = _visibleTextNear(node);
    selection = target == null
        ? null
        : Selection.collapsed(
            Position(
              path: target.node.path,
              offset: target.atEnd ? target.node.delta?.length ?? 0 : 0,
            ),
          );
  }

  ({Node node, bool atEnd})? _visibleTextNear(Node hidden) {
    bool visibleText(Node node) => node.delta != null && !isHidden(node);
    for (Node? next = hidden.next; next != null; next = next.next) {
      if (visibleText(next)) return (node: next, atEnd: false);
    }
    for (Node? previous = hidden.previous; previous != null;) {
      if (visibleText(previous)) return (node: previous, atEnd: true);
      previous = previous.previous;
    }
    return null;
  }

  @override
  void dispose() {
    selectionNotifier.removeListener(_keepSelectionVisible);
    super.dispose();
  }
}

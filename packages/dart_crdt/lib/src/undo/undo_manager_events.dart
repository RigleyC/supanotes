part of 'undo_manager.dart';

/// Stack direction represented by an undo-manager event.
enum StackItemEventType {
  /// Event relates to the undo stack.
  undo,

  /// Event relates to the redo stack.
  redo,
}

/// Event emitted when a stack item is added, updated, or popped.
final class StackItemEvent {
  /// Creates a stack item event.
  StackItemEvent({
    required this.stackItem,
    required this.type,
    this.origin,
    Map<Object, List<Object>> changedParentTypes = const {},
  }) : changedParentTypes = _copyChangedParentTypes(changedParentTypes);

  /// Stack item associated with the event.
  final StackItem stackItem;

  /// Origin of the captured transaction, if any.
  final Object? origin;

  /// Stack direction associated with this event.
  final StackItemEventType type;

  /// Parent type events collected by the captured transaction.
  final Map<Object, List<Object>> changedParentTypes;
}

/// Event emitted when undo and/or redo stacks are cleared.
final class StackClearedEvent {
  /// Creates a stack-cleared event.
  const StackClearedEvent({
    required this.undoStackCleared,
    required this.redoStackCleared,
  });

  /// Whether the undo stack was cleared.
  final bool undoStackCleared;

  /// Whether the redo stack was cleared.
  final bool redoStackCleared;
}

Map<Object, List<Object>> _copyChangedParentTypes(
  Map<Object, List<Object>> source,
) {
  return Map<Object, List<Object>>.unmodifiable({
    for (final entry in source.entries)
      entry.key: List<Object>.unmodifiable(entry.value),
  });
}

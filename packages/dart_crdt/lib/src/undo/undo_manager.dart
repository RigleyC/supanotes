/// Undo and redo stack tracking primitives.
library;

import 'dart:async';
import 'dart:collection';

import '../content/content.dart';
import '../doc/doc.dart';
import '../events/event_handler.dart';
import '../metadata/content_ids.dart';
import '../metadata/id_range.dart';
import '../metadata/id_set.dart';
import '../structs/abstract_struct.dart';
import '../structs/id.dart';
import '../structs/struct_store.dart';

part 'stack_item.dart';
part 'undo_manager_events.dart';
part 'undo_manager_capture.dart';
part 'undo_manager_apply.dart';
part 'undo_manager_scope.dart';

/// Decides whether [transaction] should be captured.
typedef UndoCaptureTransaction = bool Function(Transaction transaction);

/// Decides whether [item] may be deleted by undo or redo behavior.
typedef UndoDeleteFilter = bool Function(Item item);

/// Tracks undo and redo stack items for a document or shared-type scope.
///
/// Scope the manager to a shared type when only local edits to that type should
/// be undoable.
///
/// ```dart
/// final doc = Doc();
/// final body = doc.getText('body');
/// final undo = UndoManager(body);
///
/// body.insertText(0, 'draft');
/// undo.undo();
/// undo.redo();
/// undo.destroy();
/// ```
final class UndoManager {
  /// Creates a manager for [scope].
  ///
  /// [scope] may be a [Doc], a [SharedType], or an iterable of either. When
  /// [scope] is empty, [doc] is used as the document-wide scope.
  UndoManager(
    Object? scope, {
    Duration captureTimeout = const Duration(milliseconds: 500),
    UndoCaptureTransaction? captureTransaction,
    UndoDeleteFilter? deleteFilter,
    Set<Object?>? trackedOrigins,
    this.ignoreRemoteMapChanges = false,
    Doc? doc,
  })  : doc = doc ?? _docFromScope(scope),
        captureTimeout = _checkCaptureTimeout(captureTimeout),
        captureTransaction = captureTransaction ?? _captureEveryTransaction,
        deleteFilter = deleteFilter ?? _deleteEveryItem {
    _trackedOrigins.addAll(trackedOrigins ?? <Object?>{null});
    _trackedOrigins.add(this);
    addToScope(scope);
    if (_scope.isEmpty) {
      _scope.add(this.doc);
    }
    _afterTransactionSubscription = this.doc.afterTransaction.add(
          (transaction) => _captureAfterTransaction(this, transaction),
        );
    unawaited(this.doc.whenDestroyed.then((_) => destroy()));
  }

  final List<Object> _scope = <Object>[];
  final List<StackItem> _undoStack = <StackItem>[];
  final List<StackItem> _redoStack = <StackItem>[];
  final Set<Object?> _trackedOrigins = <Object?>{};
  final EventHandler<StackItemEvent> _stackItemAdded =
      EventHandler<StackItemEvent>();
  final EventHandler<StackItemEvent> _stackItemUpdated =
      EventHandler<StackItemEvent>();
  final EventHandler<StackItemEvent> _stackItemPopped =
      EventHandler<StackItemEvent>();
  final EventHandler<StackClearedEvent> _stackCleared =
      EventHandler<StackClearedEvent>();

  late final EventSubscription _afterTransactionSubscription;
  int _lastChange = 0;
  bool _undoing = false;
  bool _redoing = false;
  bool _isDestroyed = false;

  /// Document observed by this manager.
  final Doc doc;

  /// Maximum gap between transactions that should merge into one stack item.
  final Duration captureTimeout;

  /// Predicate used to decide whether transactions are captured.
  final UndoCaptureTransaction captureTransaction;

  /// Predicate used by later undo/redo deletion behavior.
  final UndoDeleteFilter deleteFilter;

  /// Whether later map redo behavior may overwrite remote map changes.
  final bool ignoreRemoteMapChanges;

  /// Event emitted when a stack item is created.
  EventHandler<StackItemEvent> get stackItemAdded => _stackItemAdded;

  /// Event emitted when the latest stack item is merged with a transaction.
  EventHandler<StackItemEvent> get stackItemUpdated => _stackItemUpdated;

  /// Event emitted when a stack item is popped by [undo] or [redo].
  EventHandler<StackItemEvent> get stackItemPopped => _stackItemPopped;

  /// Event emitted when [clear] removes at least one stack item.
  EventHandler<StackClearedEvent> get stackCleared => _stackCleared;

  /// Scope values observed by this manager.
  List<Object> get scope => List<Object>.unmodifiable(_scope);

  /// Undo stack from oldest to newest item.
  List<StackItem> get undoStack => List<StackItem>.unmodifiable(_undoStack);

  /// Redo stack from oldest to newest item.
  List<StackItem> get redoStack => List<StackItem>.unmodifiable(_redoStack);

  /// Origins whose transactions are captured.
  Set<Object?> get trackedOrigins => Set<Object?>.unmodifiable(
        _trackedOrigins,
      );

  /// Whether [undo] is currently popping an item.
  bool get undoing => _undoing;

  /// Whether [redo] is currently popping an item.
  bool get redoing => _redoing;

  /// Whether [destroy] has detached this manager from [doc].
  bool get isDestroyed => _isDestroyed;

  /// Whether undo stack items are available.
  bool canUndo() => _undoStack.isNotEmpty;

  /// Whether redo stack items are available.
  bool canRedo() => _redoStack.isNotEmpty;

  /// Extends the capture scope.
  void addToScope(Object? value) {
    for (final entry in _normalizeScope(value)) {
      if (!_scope.any((existing) => identical(existing, entry))) {
        _scope.add(entry);
      }
    }
  }

  /// Adds [origin] to the tracked-origin set.
  void addTrackedOrigin(Object? origin) {
    _trackedOrigins.add(origin);
  }

  /// Removes [origin] from the tracked-origin set.
  bool removeTrackedOrigin(Object? origin) => _trackedOrigins.remove(origin);

  /// Prevents the next transaction from merging with the current stack item.
  void stopCapturing() {
    _lastChange = 0;
  }

  /// Clears selected stacks and emits [stackCleared] when anything changed.
  void clear({bool undoStack = true, bool redoStack = true}) {
    final undoCleared = undoStack && _undoStack.isNotEmpty;
    final redoCleared = redoStack && _redoStack.isNotEmpty;
    if (!undoCleared && !redoCleared) {
      return;
    }
    if (undoStack) {
      _undoStack.clear();
    }
    if (redoStack) {
      _redoStack.clear();
    }
    _stackCleared.emit(
      StackClearedEvent(
        undoStackCleared: undoCleared,
        redoStackCleared: redoCleared,
      ),
    );
  }

  /// Pops the latest undo stack item and stages it on the redo stack.
  StackItem? undo() {
    return _popStackItem(this, _undoStack, _redoStack, StackItemEventType.undo);
  }

  /// Pops the latest redo stack item and stages it on the undo stack.
  StackItem? redo() {
    return _popStackItem(this, _redoStack, _undoStack, StackItemEventType.redo);
  }

  /// Detaches this manager from document events.
  void destroy() {
    if (_isDestroyed) {
      return;
    }
    _isDestroyed = true;
    _trackedOrigins.remove(this);
    _afterTransactionSubscription.cancel();
    _stackItemAdded.clear();
    _stackItemUpdated.clear();
    _stackItemPopped.clear();
    _stackCleared.clear();
  }
}

bool _captureEveryTransaction(Transaction transaction) => true;

bool _deleteEveryItem(Item item) => true;

/// Undoes the selected [contentIds] in [doc].
///
/// The helper creates a short-lived manager, pushes the selected ranges as one
/// stack item, and returns the item produced by [UndoManager.undo].
StackItem? undoContentIds(
  Doc doc,
  ContentIds contentIds, {
  UndoDeleteFilter? deleteFilter,
}) {
  final manager = UndoManager(doc, deleteFilter: deleteFilter);
  manager._undoStack.add(
    StackItem.fromSets(
      contentIds.inserts.diff(contentIds.deletes),
      contentIds.deletes.diff(contentIds.inserts),
    ),
  );
  try {
    return manager.undo();
  } finally {
    manager.destroy();
  }
}

Duration _checkCaptureTimeout(Duration value) {
  if (value.isNegative) {
    throw ArgumentError.value(value, 'captureTimeout', 'must not be negative');
  }
  return value;
}

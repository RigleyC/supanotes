part of 'undo_manager.dart';

void _captureAfterTransaction(
  UndoManager manager,
  Transaction transaction,
) {
  if (manager._isDestroyed ||
      !manager.captureTransaction(transaction) ||
      !_transactionInScope(manager, transaction) ||
      !_tracksOrigin(manager, transaction.origin) ||
      (transaction.insertSet.isEmpty && transaction.deleteSet.isEmpty)) {
    return;
  }

  final stack = manager._undoing ? manager._redoStack : manager._undoStack;
  if (manager._undoing) {
    manager.stopCapturing();
  } else if (!manager._redoing) {
    manager.clear(undoStack: false);
  }

  final now = DateTime.now().millisecondsSinceEpoch;
  final shouldMerge = manager._lastChange > 0 &&
      now - manager._lastChange < manager.captureTimeout.inMilliseconds &&
      stack.isNotEmpty &&
      !manager._undoing &&
      !manager._redoing;
  final didAdd = !shouldMerge;
  _protectDeletedContent(manager, transaction);
  if (shouldMerge) {
    stack.last._merge(transaction.insertSet, transaction.deleteSet);
  } else {
    stack.add(StackItem.fromSets(transaction.insertSet, transaction.deleteSet));
  }
  if (!manager._undoing && !manager._redoing) {
    manager._lastChange = now;
  }
  _emitStackChange(manager, stack.last, transaction, didAdd: didAdd);
}

void _emitStackChange(
  UndoManager manager,
  StackItem item,
  Transaction transaction, {
  required bool didAdd,
}) {
  final event = StackItemEvent(
    stackItem: item,
    origin: transaction.origin,
    type: manager._undoing ? StackItemEventType.redo : StackItemEventType.undo,
    changedParentTypes: transaction.changedParentTypes,
  );
  if (didAdd) {
    manager._stackItemAdded.emit(event);
  } else {
    manager._stackItemUpdated.emit(event);
  }
}

bool _transactionInScope(UndoManager manager, Transaction transaction) {
  final changed = transaction.changed;
  final parentChanged = transaction.changedParentTypes;
  for (final entry in manager._scope) {
    if (identical(entry, manager.doc)) {
      return true;
    }
    if (changed.containsKey(entry) || parentChanged.containsKey(entry)) {
      return true;
    }
    if (entry is SharedType &&
        changed.keys.whereType<SharedType>().any(
              (type) => _isSameOrDescendant(type, entry),
            )) {
      return true;
    }
  }
  return false;
}

bool _tracksOrigin(UndoManager manager, Object? origin) {
  return manager._trackedOrigins.contains(origin) ||
      (origin != null && manager._trackedOrigins.contains(origin.runtimeType));
}

void _protectDeletedContent(UndoManager manager, Transaction transaction) {
  transaction.deleteSet.forEach((client, range) {
    for (final slice in manager.doc.store.slicesWithoutSplitting(
      client: client,
      range: range,
    )) {
      final struct = slice.struct;
      if (struct is Item && struct.deleted && _itemInScope(manager, struct)) {
        struct.keep = true;
      }
    }
  });
}

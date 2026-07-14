part of 'undo_manager.dart';

StackItem? _popStackItem(
  UndoManager manager,
  List<StackItem> from,
  List<StackItem> to,
  StackItemEventType type,
) {
  if (from.isEmpty) {
    return null;
  }

  manager
    .._undoing = type == StackItemEventType.undo
    .._redoing = type == StackItemEventType.redo
    ..stopCapturing();
  final item = from.removeLast();
  final targetLengthBefore = to.length;
  Transaction? popTransaction;
  var changed = false;
  try {
    manager.doc.transact(
      (transaction) {
        popTransaction = transaction;
        changed = _applyStackItem(manager, transaction, item);
      },
      origin: manager,
    );
  } finally {
    manager
      .._undoing = false
      .._redoing = false;
  }
  if (!changed || to.length == targetLengthBefore) {
    return null;
  }

  final captured = to.last;
  captured.meta.addAll(item.meta);
  manager._stackItemPopped.emit(
    StackItemEvent(
      stackItem: captured,
      type: type,
      origin: manager,
      changedParentTypes: popTransaction?.changedParentTypes ?? const {},
    ),
  );
  return captured;
}

bool _applyStackItem(
  UndoManager manager,
  Transaction transaction,
  StackItem item,
) {
  final target = _UndoIntegrationTarget(transaction);
  final deleted = _deleteRanges(manager, target, item._inserts);
  final restored = _restoreRanges(manager, target, item._deletes);
  return deleted || restored;
}

bool _deleteRanges(
  UndoManager manager,
  _UndoIntegrationTarget target,
  IdSet ranges,
) {
  var changed = false;
  ranges.forEach((client, range) {
    for (final struct in target.store.structsWithSplitting(
      client: client,
      range: range,
    )) {
      if (struct is Item &&
          !struct.deleted &&
          manager.deleteFilter(struct) &&
          _itemInScope(manager, struct)) {
        struct.delete(target);
        changed = true;
      }
    }
  });
  return changed;
}

bool _restoreRanges(
  UndoManager manager,
  _UndoIntegrationTarget target,
  IdSet ranges,
) {
  var changed = false;
  ranges.forEach((client, range) {
    for (final struct in target.store.structsWithSplitting(
      client: client,
      range: range,
    )) {
      if (struct is Item &&
          struct.deleted &&
          struct.redone == null &&
          struct.content is! ContentDeleted &&
          _itemInScope(manager, struct)) {
        final restored = _cloneDeletedItem(target.transaction.doc, struct);
        struct.redone = restored.id;
        restored
          ..keep = true
          ..integrate(target);
        changed = true;
      }
    }
  });
  return changed;
}

Item _cloneDeletedItem(Doc doc, Item item) {
  return Item(
    id: Id(client: doc.clientId, clock: doc.store.getClock(doc.clientId)),
    origin: item.origin,
    rightOrigin: item.rightOrigin,
    parent: item.parent,
    parentSub: item.parentSub,
    content: item.content.copy(),
  );
}

bool _itemInScope(UndoManager manager, Item item) {
  for (final entry in manager._scope) {
    if (identical(entry, manager.doc)) {
      return true;
    }
    if (entry is SharedType && item.parent?.key == entry.name) {
      return true;
    }
  }
  return false;
}

final class _UndoIntegrationTarget
    implements ItemIntegrationTarget, NestedContentLifecycleTarget {
  _UndoIntegrationTarget(this.transaction);

  final Transaction transaction;

  StructStore get store => transaction.doc.store;

  @override
  void addStruct(AbstractStruct struct) => store.addStruct(struct);

  @override
  void addInsertedRange(ClientId client, IdRange range) {
    store.addInsertedRange(client, range);
    transaction.addInsertedRange(client, range);
  }

  @override
  void addDeletedRange(ClientId client, IdRange range) {
    store.addDeletedRange(client, range);
    transaction.addDeletedRange(client, range);
  }

  @override
  void addSkippedRange(ClientId client, IdRange range) {
    store.addSkippedRange(client, range);
  }

  @override
  Item? itemContaining(Id id) => store.itemContaining(id);

  @override
  void addChangedParent(ItemParent parent, String? parentSub) {
    transaction.markChanged(parent, parentSub);
  }

  @override
  void updateSearchMarkers({
    required ItemParent parent,
    required Item item,
    required int lengthDelta,
  }) {}

  @override
  void queueMerge(Item item) => transaction.queueMerge(item);

  @override
  void markDeleted(int length) => RangeError.checkNotNegative(length, 'length');

  @override
  void clearFormattingCache() {
    transaction.shouldCleanupFormatting = true;
  }

  @override
  void markHasFormatting() {
    transaction.shouldCleanupFormatting = true;
  }

  @override
  void addSubdocument(Subdocument document) {
    transaction
      ..addSubdocument(document)
      ..doc.addSubdocument(document);
  }

  @override
  void loadSubdocument(Subdocument document) {
    transaction.loadSubdocument(document);
  }

  @override
  void removeSubdocument(Subdocument document) {
    transaction
      ..removeSubdocument(document)
      ..doc.removeSubdocument(document);
  }

  @override
  void integrateSharedType(SharedTypePlaceholder sharedType) {}

  @override
  void deleteSharedType(SharedTypePlaceholder sharedType) {}

  @override
  void gcSharedType(SharedTypePlaceholder sharedType) {}
}

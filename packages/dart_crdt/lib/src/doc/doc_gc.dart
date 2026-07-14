part of 'doc.dart';

void _cleanupStructs(Transaction transaction) {
  _cleanupFormatting(transaction);
  _garbageCollectDeletedItems(transaction);
  _mergeQueuedStructs(transaction);
  _replaceDuplicateClientId(transaction);
}

void _garbageCollectDeletedItems(Transaction transaction) {
  final doc = transaction.doc;
  if (!doc.gc || transaction.deleteSet.isEmpty) {
    return;
  }
  final target = _GcTarget(transaction);
  transaction.deleteSet.forEach((client, range) {
    for (final struct in doc.store.structsWithSplitting(
      client: client,
      range: range,
    )) {
      if (struct is Item &&
          struct.deleted &&
          !struct.keep &&
          struct.content is! ContentDeleted &&
          doc.gcFilter(struct)) {
        struct.gc(target);
        transaction.queueMerge(struct);
      }
    }
  });
}

void _mergeQueuedStructs(Transaction transaction) {
  for (final struct in transaction.mergeStructs) {
    transaction.doc.store.compactAround(struct);
  }
}

void _replaceDuplicateClientId(Transaction transaction) {
  if (transaction.local ||
      !transaction.insertSet.clients.contains(transaction.doc.clientId)) {
    return;
  }
  transaction.doc.replaceClientId();
}

final class _GcTarget
    implements ItemIntegrationTarget, NestedContentLifecycleTarget {
  const _GcTarget(this.transaction);

  final Transaction transaction;

  @override
  void addChangedParent(ItemParent parent, String? parentSub) {}

  @override
  void addDeletedRange(ClientId client, IdRange range) {}

  @override
  void addInsertedRange(ClientId client, IdRange range) {}

  @override
  void addSkippedRange(ClientId client, IdRange range) {}

  @override
  void addStruct(AbstractStruct struct) {}

  @override
  void clearFormattingCache() {
    transaction.shouldCleanupFormatting = true;
  }

  @override
  void addSubdocument(Subdocument document) {}

  @override
  void deleteSharedType(SharedTypePlaceholder sharedType) {}

  @override
  void gcSharedType(SharedTypePlaceholder sharedType) {}

  @override
  void integrateSharedType(SharedTypePlaceholder sharedType) {}

  @override
  void loadSubdocument(Subdocument document) {}

  @override
  void markDeleted(int length) => RangeError.checkNotNegative(length, 'length');

  @override
  void markHasFormatting() {
    transaction.shouldCleanupFormatting = true;
  }

  @override
  Item? itemContaining(Id id) => transaction.doc.store.itemContaining(id);

  @override
  void queueMerge(Item item) => transaction.queueMerge(item);

  @override
  void removeSubdocument(Subdocument document) {}

  @override
  void updateSearchMarkers({
    required ItemParent parent,
    required Item item,
    required int lengthDelta,
  }) {}
}

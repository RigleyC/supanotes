part of 'doc.dart';

final class _LocalTextIntegrationTarget
    implements ItemIntegrationTarget, NestedContentLifecycleTarget {
  _LocalTextIntegrationTarget(this.transaction);

  final Transaction transaction;

  StructStore get store => transaction.doc.store;

  @override
  void addStruct(AbstractStruct struct) {
    store.addStruct(struct);
  }

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
  void queueMerge(Item item) {
    transaction.queueMerge(item);
  }

  @override
  void markDeleted(int length) {
    RangeError.checkNotNegative(length, 'length');
  }

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

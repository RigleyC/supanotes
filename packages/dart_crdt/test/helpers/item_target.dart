import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/metadata/id_range.dart';
import 'package:dart_crdt/src/metadata/id_set.dart';
import 'package:dart_crdt/src/structs/abstract_struct.dart';
import 'package:dart_crdt/src/structs/id.dart';

/// Search-marker update captured by [ItemTarget].
final class MarkerUpdate {
  /// Creates a captured marker update.
  const MarkerUpdate({
    required this.parent,
    required this.item,
    required this.lengthDelta,
  });

  /// Parent whose markers changed.
  final ItemParent parent;

  /// Item where the change happened.
  final Item item;

  /// Signed visible length delta.
  final int lengthDelta;
}

/// Parent-change event captured by [ItemTarget].
final class ChangedParent {
  /// Creates a captured parent change.
  const ChangedParent(this.parent, this.parentSub);

  /// Changed parent.
  final ItemParent parent;

  /// Changed map key, or `null` for sequence content.
  final String? parentSub;
}

/// Test target that records item, struct, and nested-content side effects.
final class ItemTarget
    implements ItemIntegrationTarget, NestedContentLifecycleTarget {
  /// Stored structs in integration order.
  final List<AbstractStruct> structs = <AbstractStruct>[];

  /// Inserted ids.
  final IdSet inserted = IdSet();

  /// Deleted ids.
  final IdSet deleted = IdSet();

  /// Skipped ids.
  final IdSet skipped = IdSet();

  /// Changed parents.
  final List<ChangedParent> changedParents = <ChangedParent>[];

  /// Search marker updates.
  final List<MarkerUpdate> markerUpdates = <MarkerUpdate>[];

  /// Items queued for merge.
  final List<Item> mergeQueue = <Item>[];

  /// Added subdocuments.
  final List<Subdocument> addedDocuments = <Subdocument>[];

  /// Loaded subdocuments.
  final List<Subdocument> loadedDocuments = <Subdocument>[];

  /// Removed subdocuments.
  final List<Subdocument> removedDocuments = <Subdocument>[];

  /// Integrated shared type placeholders.
  final List<SharedTypePlaceholder> integratedTypes = <SharedTypePlaceholder>[];

  /// Deleted shared type placeholders.
  final List<SharedTypePlaceholder> deletedTypes = <SharedTypePlaceholder>[];

  /// Garbage-collected shared type placeholders.
  final List<SharedTypePlaceholder> gcTypes = <SharedTypePlaceholder>[];

  /// Deleted content lengths reported by content hooks.
  final List<int> deletedContentLengths = <int>[];

  /// Whether formatting cache clearing was requested.
  bool formatCleared = false;

  /// Whether formatting content was observed.
  bool hasFormatting = false;

  @override
  void addChangedParent(ItemParent parent, String? parentSub) {
    changedParents.add(ChangedParent(parent, parentSub));
  }

  @override
  void addDeletedRange(ClientId client, IdRange range) {
    deleted.addRange(client, range);
  }

  @override
  void addInsertedRange(ClientId client, IdRange range) {
    inserted.addRange(client, range);
  }

  @override
  void addSkippedRange(ClientId client, IdRange range) {
    skipped.addRange(client, range);
  }

  @override
  void addStruct(AbstractStruct struct) {
    structs.add(struct);
  }

  @override
  void addSubdocument(Subdocument document) {
    addedDocuments.add(document);
  }

  @override
  void clearFormattingCache() {
    formatCleared = true;
  }

  @override
  void deleteSharedType(SharedTypePlaceholder sharedType) {
    deletedTypes.add(sharedType);
  }

  @override
  void gcSharedType(SharedTypePlaceholder sharedType) {
    gcTypes.add(sharedType);
  }

  @override
  void integrateSharedType(SharedTypePlaceholder sharedType) {
    integratedTypes.add(sharedType);
  }

  @override
  Item? itemContaining(Id id) {
    for (final struct in structs.reversed) {
      if (struct is Item &&
          struct.id.client == id.client &&
          struct.id.clock.value <= id.clock.value &&
          id.clock.value < struct.end) {
        return struct;
      }
    }
    return null;
  }

  @override
  void loadSubdocument(Subdocument document) {
    loadedDocuments.add(document);
  }

  @override
  void markDeleted(int length) {
    deletedContentLengths.add(length);
  }

  @override
  void markHasFormatting() {
    hasFormatting = true;
  }

  @override
  void queueMerge(Item item) {
    mergeQueue.add(item);
  }

  @override
  void removeSubdocument(Subdocument document) {
    removedDocuments.add(document);
  }

  @override
  void updateSearchMarkers({
    required ItemParent parent,
    required Item item,
    required int lengthDelta,
  }) {
    markerUpdates.add(
      MarkerUpdate(parent: parent, item: item, lengthDelta: lengthDelta),
    );
  }
}

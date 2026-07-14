part of 'abstract_struct.dart';

/// Resolves item ids to the stored item that contains that clock.
abstract interface class ItemLookup {
  /// Returns the item containing [id], or `null` when it is unknown.
  Item? itemContaining(Id id);
}

/// Receives item-specific integration side effects.
abstract interface class ItemIntegrationTarget
    implements StructIntegrationTarget, ContentLifecycleTarget, ItemLookup {
  /// Records that [parent] changed at [parentSub].
  void addChangedParent(ItemParent parent, String? parentSub);

  /// Updates search markers after an insertion or deletion length change.
  void updateSearchMarkers({
    required ItemParent parent,
    required Item item,
    required int lengthDelta,
  });

  /// Queues [item] for a later merge pass.
  void queueMerge(Item item);
}

/// Minimal parent list/map state used while full shared types are built.
final class ItemParent {
  /// Creates parent state for a root or nested shared type.
  ItemParent({
    required this.key,
    this.definingItemId,
    bool isDeleted = false,
  }) : _isDeleted = isDeleted;

  /// Stable parent key used by root placeholder binary writing.
  final String key;

  /// Id of the `ContentType` item that defines this nested type, or `null` for
  /// a root parent. When set, items are encoded with a parent-id reference
  /// instead of a root-name string.
  final Id? definingItemId;

  Item? _start;
  final Map<String, Item> _currentBySubKey = <String, Item>{};
  int _length = 0;
  bool _isDeleted;

  /// First sequence item for this parent.
  Item? get start => _start;

  /// Visible countable length for sequence content.
  int get length => _length;

  /// Whether this parent has been deleted.
  bool get isDeleted => _isDeleted;

  /// Marks this parent as deleted.
  void markDeleted() {
    _isDeleted = true;
  }

  /// Returns the current item for a map-style [parentSub] key.
  Item? currentFor(String parentSub) => _currentBySubKey[parentSub];

  /// Map-style keys that have a current item, in first-set order.
  Iterable<String> get subKeys => _currentBySubKey.keys;

  /// Returns an immutable snapshot of items linked under [parentSub].
  List<Item> items({String? parentSub}) {
    final result = <Item>[];
    var item = _firstFor(parentSub);
    while (item != null) {
      if (identical(item.parent, this) && item.parentSub == parentSub) {
        result.add(item);
      }
      item = item.right;
    }
    return List<Item>.unmodifiable(result);
  }

  Item? _firstFor(String? parentSub) {
    if (parentSub == null) {
      return _start;
    }
    var item = _currentBySubKey[parentSub];
    while (item?.left != null && item!.left!.parentSub == parentSub) {
      item = item.left;
    }
    return item;
  }

  void _setStart(Item? item) {
    _start = item;
  }

  void _setCurrent(String parentSub, Item? item) {
    if (item == null) {
      _currentBySubKey.remove(parentSub);
      return;
    }
    _currentBySubKey[parentSub] = item;
  }

  void _increaseLength(int delta) {
    RangeError.checkNotNegative(delta, 'delta');
    _length += delta;
  }

  void _decreaseLength(int delta) {
    RangeError.checkNotNegative(delta, 'delta');
    if (delta > _length) {
      throw StateError('Parent length cannot become negative.');
    }
    _length -= delta;
  }
}

/// Result of resolving an item through its redo chain.
final class FollowRedoneResult {
  /// Creates a redo resolution result.
  const FollowRedoneResult({
    required this.item,
    required this.diff,
  });

  /// The final item reached through redo links.
  final Item item;

  /// Offset inside [item] corresponding to the original id.
  final int diff;
}

/// Follows redo links starting at [id].
FollowRedoneResult followRedone(ItemLookup lookup, Id id) {
  var nextId = id;
  var diff = 0;
  while (true) {
    if (diff > 0) {
      nextId = nextId.advance(diff);
    }
    final item = lookup.itemContaining(nextId);
    if (item == null) {
      throw StateError('Cannot follow redo for missing item $nextId.');
    }
    diff = nextId.clock.value - item.id.clock.value;
    final redone = item.redone;
    if (redone == null) {
      return FollowRedoneResult(item: item, diff: diff);
    }
    nextId = redone;
  }
}

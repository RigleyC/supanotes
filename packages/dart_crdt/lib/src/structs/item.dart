part of 'abstract_struct.dart';

const int _itemKeepBit = 1;
const int _itemCountableBit = 2;
const int _itemDeletedBit = 4;
const int _itemMarkerBit = 8;
const int _itemContentInfoMask = 0x1f;
const int _itemHasParentSubBit = 0x20;
const int _itemHasRightOriginBit = 0x40;
const int _itemHasOriginBit = 0x80;

/// Content-bearing CRDT struct.
final class Item extends AbstractStruct {
  /// Creates an item around [content].
  Item({
    required super.id,
    this.left,
    this.origin,
    this.right,
    this.rightOrigin,
    required this.parent,
    this.parentSub,
    required this.content,
  })  : _info = content.isCountable ? _itemCountableBit : 0,
        super(length: content.length);

  /// Item that was originally to the left.
  Id? origin;

  /// Current item to the left.
  Item? left;

  /// Current item to the right.
  Item? right;

  /// Item that was originally to the right.
  Id? rightOrigin;

  /// Parent sequence or map placeholder.
  ItemParent? parent;

  /// Optional parent map key.
  String? parentSub;

  /// Id of content that redoes this item's effect.
  Id? redone;

  /// Item content payload.
  AbstractContent content;

  int _info;

  /// Raw item info flags.
  int get info => _info;

  /// Whether this item should be retained during garbage collection.
  bool get keep => _hasFlag(_itemKeepBit);

  set keep(bool value) => _setFlag(_itemKeepBit, value);

  /// Whether this item is a search marker anchor.
  bool get marker => _hasFlag(_itemMarkerBit);

  set marker(bool value) => _setFlag(_itemMarkerBit, value);

  /// Whether this item contributes to visible sequence length.
  bool get countable => _hasFlag(_itemCountableBit);

  @override
  bool get deleted => _hasFlag(_itemDeletedBit);

  @override
  bool get isItem => true;

  @override
  int get ref => content.ref;

  /// Last id covered by this item.
  Id get lastId => length == 1 ? id : id.advance(length - 1);

  /// Next non-deleted item.
  Item? get next {
    var item = right;
    while (item != null && item.deleted) {
      item = item.right;
    }
    return item;
  }

  /// Previous non-deleted item.
  Item? get previous {
    var item = left;
    while (item != null && item.deleted) {
      item = item.left;
    }
    return item;
  }

  /// Extracted user-visible content.
  List<Object?> get values => content.content;

  /// Marks this item as deleted without applying side effects.
  void markDeleted() {
    _info |= _itemDeletedBit;
  }

  @override
  bool canMergeWith(AbstractStruct other) {
    return other is Item &&
        parentSub == other.parentSub &&
        identical(parent, other.parent) &&
        other.origin == lastId &&
        super.canMergeWith(other);
  }

  @override
  bool mergeWith(AbstractStruct other) {
    if (other is! Item ||
        !identical(right, other) ||
        other.origin != lastId ||
        rightOrigin != other.rightOrigin ||
        id.client != other.id.client ||
        end != other.id.clock.value ||
        deleted != other.deleted ||
        redone != null ||
        other.redone != null ||
        !content.mergeWith(other.content)) {
      return false;
    }
    if (other.keep) {
      keep = true;
    }
    if (other.marker) {
      marker = true;
      other.marker = false;
    }
    right = other.right;
    if (right != null) {
      right!.left = this;
    }
    if (parentSub != null && parent?.currentFor(parentSub!) == other) {
      parent?._setCurrent(parentSub!, this);
    }
    other
      ..left = null
      ..right = null;
    _extendBy(other);
    return true;
  }

  @override
  Item split(int diff) {
    _checkSplitDiff(diff, length);
    final rightItem = Item(
      id: id.advance(diff),
      left: this,
      origin: id.advance(diff - 1),
      right: right,
      rightOrigin: rightOrigin,
      parent: parent,
      parentSub: parentSub,
      content: content.splice(diff),
    );
    if (deleted) {
      rightItem.markDeleted();
    }
    rightItem
      ..keep = keep
      ..redone = redone?.advance(diff);
    if (right != null) {
      right!.left = rightItem;
    }
    right = rightItem;
    if (parentSub != null && parent?.currentFor(parentSub!) == this) {
      parent?._setCurrent(parentSub!, rightItem);
    }
    _length = diff;
    return rightItem;
  }

  @override
  void integrate(StructIntegrationTarget target, {int offset = 0}) {
    if (parent == null) {
      GC(id: id, length: length).integrate(target, offset: offset);
      return;
    }
    if (target is! ItemIntegrationTarget) {
      throw StateError('Item integration target required.');
    }
    _applyItemOffset(this, offset, target);
    final itemParent = parent!;
    left = _findItemInsertionLeft(this, target, itemParent);
    if (parentSub == null && left != null) {
      parentSub = left?.parentSub;
    }
    _connectItem(this, itemParent, target);
    if (parentSub == null && countable && !deleted) {
      itemParent._increaseLength(length);
      target.updateSearchMarkers(
        parent: itemParent,
        item: this,
        lengthDelta: length,
      );
    }
    target
      ..addInsertedRange(id.client, range)
      ..addStruct(this);
    content.integrate(target);
    target
      ..addChangedParent(itemParent, parentSub)
      ..queueMerge(this);
    if (itemParent.isDeleted || (parentSub != null && right != null)) {
      delete(target);
    }
  }

  /// Deletes this item and applies content side effects.
  void delete(ItemIntegrationTarget target) {
    if (deleted) {
      return;
    }
    final itemParent = parent;
    if (itemParent != null && parentSub == null && countable) {
      itemParent._decreaseLength(length);
      target.updateSearchMarkers(
        parent: itemParent,
        item: this,
        lengthDelta: -length,
      );
    }
    markDeleted();
    target.addDeletedRange(id.client, range);
    if (itemParent != null) {
      target.addChangedParent(itemParent, parentSub);
    }
    content.delete(target);
    target.queueMerge(this);
  }

  /// Replaces deleted content with compact deleted-content payload.
  void gc(ItemIntegrationTarget target) {
    if (!deleted) {
      throw StateError('Only deleted items can be garbage-collected.');
    }
    content.gc(target);
    content = ContentDeleted(length);
  }

  @override
  void write(ByteWriter writer, {int offset = 0, int offsetEnd = 0}) {
    final writeOrigin = offset == 0 ? origin : id.advance(offset - 1);
    var header = content.ref & _itemContentInfoMask;
    if (writeOrigin != null) {
      header |= _itemHasOriginBit;
    }
    if (rightOrigin != null) {
      header |= _itemHasRightOriginBit;
    }
    if (parentSub != null) {
      header |= _itemHasParentSubBit;
    }
    writer.writeByte(header);
    writeOrigin?.write(writer);
    rightOrigin?.write(writer);
    if (writeOrigin == null && rightOrigin == null) {
      final itemParent = parent;
      if (itemParent == null) {
        throw StateError('Cannot write item without a parent reference.');
      }
      writeRootKey(writer, itemParent.key);
      if (parentSub != null) {
        writeString(writer, parentSub!);
      }
    }
    content.write(writer, offset: offset, offsetEnd: offsetEnd);
  }

  bool _hasFlag(int bit) => (_info & bit) != 0;

  void _setFlag(int bit, bool value) {
    if (_hasFlag(bit) != value) {
      _info ^= bit;
    }
  }
}

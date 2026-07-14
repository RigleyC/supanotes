part of 'abstract_struct.dart';

void _applyItemOffset(Item item, int offset, ItemLookup lookup) {
  RangeError.checkValueInInterval(offset, 0, item.length - 1, 'offset');
  if (offset == 0) {
    return;
  }
  final oldId = item.id;
  final newOrigin = Id(
    client: oldId.client,
    clock: Clock(oldId.clock.value + offset - 1),
  );
  item
    ..content = item.content.splice(offset)
    .._id = oldId.advance(offset)
    .._length = item.content.length
    ..origin = newOrigin
    ..left = lookup.itemContaining(newOrigin);
}

Item? _findItemInsertionLeft(
  Item item,
  ItemIntegrationTarget target,
  ItemParent itemParent,
) {
  var insertionLeft = item.left ?? _originItem(item, target);
  var cursor = insertionLeft?.right ?? itemParent._firstFor(item.parentSub);
  final conflicting = <Item>{};
  final beforeOrigin = <Item>{};
  while (cursor != null && !identical(cursor, item.right)) {
    beforeOrigin.add(cursor);
    conflicting.add(cursor);
    if (item.origin == cursor.origin) {
      if (cursor.id.client.value < item.id.client.value) {
        insertionLeft = cursor;
        conflicting.clear();
      } else if (item.rightOrigin == cursor.rightOrigin) {
        break;
      }
    } else {
      final cursorOrigin = _originItem(cursor, target);
      if (cursorOrigin != null && beforeOrigin.contains(cursorOrigin)) {
        if (!conflicting.contains(cursorOrigin)) {
          insertionLeft = cursor;
          conflicting.clear();
        }
      } else {
        break;
      }
    }
    cursor = cursor.right;
  }
  return insertionLeft;
}

Item? _originItem(Item item, ItemLookup lookup) {
  final leftOrigin = item.origin;
  return leftOrigin == null ? null : lookup.itemContaining(leftOrigin);
}

void _connectItem(
  Item item,
  ItemParent itemParent,
  ItemIntegrationTarget target,
) {
  final insertionLeft = item.left;
  final nextRight = insertionLeft == null
      ? itemParent._firstFor(item.parentSub)
      : insertionLeft.right;
  item.right = nextRight;
  if (insertionLeft != null) {
    insertionLeft.right = item;
  } else if (item.parentSub == null) {
    itemParent._setStart(item);
  }
  if (nextRight != null) {
    nextRight.left = item;
  } else if (item.parentSub != null) {
    itemParent._setCurrent(item.parentSub!, item);
    insertionLeft?.delete(target);
  }
}

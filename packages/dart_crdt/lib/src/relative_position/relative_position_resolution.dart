part of 'relative_position.dart';

/// Returns the visible length contribution for [item].
typedef RelativePositionContentLength = int Function(Item item);

/// Creates a relative position from [type] and visible [index].
///
/// Relative positions can be stored with presence or cursor state and resolved
/// again after concurrent inserts or deletes.
///
/// ```dart
/// final doc = Doc();
/// final body = doc.getText('body');
/// body.insertText(0, 'abc');
///
/// final position = createRelativePositionFromTypeIndex(body, 1);
/// final absolute = createAbsolutePositionFromRelativePosition(position, doc);
/// assert(absolute?.index == 1);
/// ```
RelativePosition createRelativePositionFromTypeIndex(
  SharedType type,
  int index, {
  int assoc = 0,
  RelativePositionContentLength contentLength = defaultRelativeContentLength,
}) {
  RangeError.checkNotNegative(index, 'index');
  _checkAssoc(assoc);
  final doc = type.doc;
  final parent = doc?.storeParentForType(type);
  if (doc == null || parent == null) {
    throw UnsupportedError(
      'Only integrated shared types support relative positions.',
    );
  }
  // A nested type anchors end-of-type positions to its defining item id; a root
  // type uses its root name.
  final typeId = parent.definingItemId;
  final rootName = typeId == null ? _rootNameFor(type) : null;
  if (rootName == null && typeId == null) {
    throw UnsupportedError(
      'Only integrated shared types support relative positions.',
    );
  }
  final totalLength = _parentLength(parent, contentLength);
  RangeError.checkValueInInterval(index, 0, totalLength, 'index');

  var remaining = index;
  if (assoc < 0) {
    if (remaining == 0) {
      return RelativePosition(rootName: rootName, typeId: typeId, assoc: assoc);
    }
    remaining -= 1;
  }

  for (final item in parent.items()) {
    final length = contentLength(item);
    if (length > remaining) {
      return RelativePosition(
        rootName: rootName,
        typeId: typeId,
        itemId: item.id.advance(remaining),
        assoc: assoc,
      );
    }
    remaining -= length;
    if (item.right == null && assoc < 0) {
      return RelativePosition(
        rootName: rootName,
        typeId: typeId,
        itemId: item.lastId,
        assoc: assoc,
      );
    }
  }
  return RelativePosition(rootName: rootName, typeId: typeId, assoc: assoc);
}

/// Resolves [position] in [doc], or returns `null` while required content is missing.
AbsolutePosition? createAbsolutePositionFromRelativePosition(
  RelativePosition position,
  Doc doc, {
  bool followRedoneItems = true,
  RelativePositionContentLength contentLength = defaultRelativeContentLength,
}) {
  final itemId = position.itemId;
  if (itemId != null) {
    return _absoluteFromItem(
      position,
      doc,
      itemId,
      followRedoneItems: followRedoneItems,
      contentLength: contentLength,
    );
  }

  final rootName = position.rootName;
  if (rootName != null) {
    final type = _typeForRootName(doc, rootName);
    final parent = doc.itemParentForKey(rootName);
    final index =
        position.assoc >= 0 ? _parentLength(parent, contentLength) : 0;
    return AbsolutePosition(type: type, index: index, assoc: position.assoc);
  }

  final typeId = position.typeId;
  if (typeId != null) {
    return _absoluteFromTypeId(
      position,
      doc,
      typeId,
      followRedoneItems: followRedoneItems,
    );
  }
  throw StateError('Relative position has no anchor.');
}

/// Default visible content length for relative-position resolution.
int defaultRelativeContentLength(Item item) {
  return item.deleted || !item.countable ? 0 : item.length;
}

AbsolutePosition? _absoluteFromItem(
  RelativePosition position,
  Doc doc,
  Id itemId, {
  required bool followRedoneItems,
  required RelativePositionContentLength contentLength,
}) {
  if (doc.store.getClock(itemId.client).value <= itemId.clock.value) {
    return null;
  }
  final resolved = _resolveItem(doc, itemId, followRedoneItems);
  if (resolved == null) {
    return null;
  }
  final item = resolved.item;
  final parent = item.parent;
  if (parent == null || parent.isDeleted) {
    return null;
  }

  var index = contentLength(item) == 0
      ? 0
      : resolved.diff + (position.assoc >= 0 ? 0 : 1);
  var left = item.left;
  while (left != null) {
    index += contentLength(left);
    left = left.left;
  }
  return AbsolutePosition(
    type: _typeForParent(doc, parent),
    index: index,
    assoc: position.assoc,
  );
}

AbsolutePosition? _absoluteFromTypeId(
  RelativePosition position,
  Doc doc,
  Id typeId, {
  required bool followRedoneItems,
}) {
  if (doc.store.getClock(typeId.client).value <= typeId.clock.value) {
    return null;
  }
  final resolved = _resolveItem(doc, typeId, followRedoneItems);
  final item = resolved?.item;
  if (item == null || item.deleted || item.content is! ContentType) {
    return null;
  }
  // Resolve to the live, store-backed nested type so the index reflects its
  // real content and the result is usable for cursor mapping.
  final type = doc.liveNestedTypeForItem(item);
  final index = position.assoc >= 0 ? type.length : 0;
  return AbsolutePosition(type: type, index: index, assoc: position.assoc);
}

FollowRedoneResult? _resolveItem(
  Doc doc,
  Id id,
  bool followRedoneItems,
) {
  try {
    if (followRedoneItems) {
      return followRedone(doc.store, id);
    }
    final item = doc.store.itemContaining(id);
    if (item == null) {
      return null;
    }
    return FollowRedoneResult(
      item: item,
      diff: id.clock.value - item.id.clock.value,
    );
  } on StateError {
    return null;
  }
}

SharedType _typeForParent(Doc doc, ItemParent parent) {
  final definingId = parent.definingItemId;
  if (definingId != null) {
    final existing = doc.sharedTypeForItemId(definingId);
    if (existing != null) {
      return existing;
    }
    final definingItem = doc.store.itemContaining(definingId);
    if (definingItem != null && definingItem.content is ContentType) {
      return doc.liveNestedTypeForItem(definingItem);
    }
  }
  return _typeForRootName(doc, parent.key);
}

SharedType _typeForRootName(Doc doc, String rootName) {
  final existing = doc.share[rootName];
  if (existing != null) {
    return existing;
  }
  return doc.get(rootName);
}

String? _rootNameFor(SharedType type) {
  final doc = type.doc;
  if (doc == null || !type.isRoot) {
    return null;
  }
  for (final entry in doc.share.entries) {
    if (identical(entry.value, type)) {
      return entry.key;
    }
  }
  return type.name;
}

int _parentLength(
  ItemParent parent,
  RelativePositionContentLength contentLength,
) {
  var length = 0;
  for (final item in parent.items()) {
    length += contentLength(item);
  }
  return length;
}

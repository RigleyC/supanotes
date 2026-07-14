part of 'doc.dart';

void _syncRootTextFromStoreIfNeeded(SharedType type) {
  if (type.kind != SharedTypeKind.text && type.kind != SharedTypeKind.xmlText) {
    return;
  }
  final parent = _storeParentFor(type);
  if (parent == null) {
    return;
  }
  final values = _rootTextValues(type.doc!, parent);
  if (_sameTextValues(type._sequence, values)) {
    return;
  }
  type._sequence
    ..clear()
    ..addAll(values);
  type._textAttributes
    ..clear()
    ..addAll(
      List<DeltaAttributes>.filled(values.length, DeltaAttributes.empty),
    );
  type._bindSequenceChildren();
  type._searchMarkers.clear();
}

String? _rootKeyFor(SharedType type) {
  final document = type.doc;
  if (document == null || !type.isRoot) {
    return null;
  }
  for (final entry in document.share.entries) {
    if (identical(entry.value, type)) {
      return entry.key.isEmpty ? null : entry.key;
    }
  }
  return type.name.isEmpty ? null : type.name;
}

/// Returns the store [ItemParent] backing [type], or `null` when [type] is not
/// store-backed.
///
/// This is the single gate that decides whether a shared type's content lives
/// in the struct store (and therefore syncs over the wire) or only in the
/// in-memory model. Today it resolves only root types via [_rootKeyFor]; later
/// milestones extend it to nested types (addressed by their defining item id).
ItemParent? _storeParentFor(SharedType type) {
  final nested = type._nestedParent;
  if (nested != null) {
    return nested;
  }
  final rootKey = _rootKeyFor(type);
  if (rootKey == null) {
    return null;
  }
  return type.doc!.itemParentForKey(rootKey);
}

List<Object?> _rootTextValues(Doc doc, ItemParent parent) {
  final values = <Object?>[];
  for (final item in parent.items()) {
    if (item.deleted || !item.countable) {
      continue;
    }
    switch (item.content) {
      case ContentString(:final value):
        values.addAll(_unicodeScalars(value));
      case ContentType():
        values.add(_liveNestedType(doc, item));
      case final content:
        values.addAll(content.content);
    }
  }
  return values;
}

bool _sameTextValues(List<Object?> left, List<Object?> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (!_sameTextValue(left[index], right[index])) {
      return false;
    }
  }
  return true;
}

bool _sameTextValue(Object? left, Object? right) {
  if (left is Map && right is Map) {
    if (left.length != right.length) {
      return false;
    }
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_sameTextValue(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (!_sameTextValue(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}

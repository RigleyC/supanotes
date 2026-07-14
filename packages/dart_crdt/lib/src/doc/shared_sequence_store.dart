part of 'doc.dart';

/// Resolves a store [parent] back to its live root [SharedType], or `null`.
///
/// Root parents are keyed by name; nested parents (added in a later milestone)
/// resolve via their defining item id.
SharedType? _typeForItemParent(Doc doc, ItemParent parent) {
  final definingId = parent.definingItemId;
  if (definingId != null) {
    return doc.sharedTypeForItemId(definingId);
  }
  return doc.share[parent.key];
}

/// Returns the live nested [SharedType] defined by the `ContentType` [item],
/// creating and binding it to its store parent on first access.
SharedType _liveNestedType(Doc doc, Item item) {
  final existing = doc.sharedTypeForItemId(item.id);
  if (existing != null) {
    return existing;
  }
  final placeholder = (item.content as ContentType).sharedType;
  // A locally inserted type is stored as itself, so reuse the live object; a
  // remote-decoded placeholder becomes a fresh type bound to the same parent.
  final type = placeholder is SharedType
      ? placeholder
      : SharedType(kind: placeholder.kind, name: placeholder.name);
  type._bindNestedParent(doc, doc.itemParentForItemId(item.id));
  doc.registerSharedTypeForItemId(item.id, type);
  return type;
}

/// Binds the nested type defined by [item] and flushes its prelim content into
/// the store. Called after a `ContentType` item is integrated locally.
void _integrateNestedValue(Transaction transaction, Item item) {
  final type = _liveNestedType(transaction.doc, item);
  _flushPrelimContent(transaction, type);
}

/// Replays a freshly-bound nested type's in-memory prelim content into the
/// store so it serializes. Nested-type values recurse through the same
/// integration path.
void _flushPrelimContent(Transaction transaction, SharedType type) {
  switch (type.kind) {
    case SharedTypeKind.map:
    case SharedTypeKind.xmlHook:
      if (type._attrs.isEmpty) {
        return;
      }
      final prelim = Map<String, _AttributeEntry>.of(type._attrs);
      type._attrs.clear();
      for (final entry in prelim.entries) {
        _setRootMapAttr(transaction, type, entry.key, entry.value.value);
      }
      _syncMapFromStoreIfNeeded(type);
    case SharedTypeKind.text:
    case SharedTypeKind.xmlText:
      if (type._sequence.isEmpty) {
        return;
      }
      final prelim = List<Object?>.of(type._sequence);
      type._sequence.clear();
      type._textAttributes.clear();
      _insertRootTextValues(transaction, type, 0, prelim);
      _syncSharedTypeView(type);
    case SharedTypeKind.array:
    case SharedTypeKind.xmlElement:
    case SharedTypeKind.xmlFragment:
      if (type._sequence.isEmpty) {
        return;
      }
      final prelim = List<Object?>.of(type._sequence);
      type._sequence.clear();
      _insertRootSequenceValues(transaction, type, 0, prelim);
      _syncSharedTypeView(type);
  }
}

/// Rebuilds [type]'s in-memory view from the struct store when it is
/// store-backed. Dispatches by kind so callers can sync any sequence-like type
/// without knowing whether it is text or an array.
void _syncSharedTypeView(SharedType type) {
  // Each helper returns early for kinds it does not handle, so calling all
  // three is safe and keeps a single sync entry point for the shared read paths.
  _syncRootTextFromStoreIfNeeded(type);
  _syncRootSequenceFromStoreIfNeeded(type);
  _syncMapFromStoreIfNeeded(type);
}

/// Rebuilds a store-backed array's in-memory `_sequence` cache from the store.
///
/// Unlike text, array values are not exploded into Unicode scalars: each stored
/// value (or each element of a batched [ContentAny]) is one visible element.
void _syncRootSequenceFromStoreIfNeeded(SharedType type) {
  if (type.kind != SharedTypeKind.array) {
    return;
  }
  final parent = _storeParentFor(type);
  if (parent == null) {
    return;
  }
  final values = _rootSequenceValues(type.doc!, parent);
  if (_sameTextValues(type._sequence, values)) {
    return;
  }
  type._sequence
    ..clear()
    ..addAll(values);
  type._bindSequenceChildren();
  type._searchMarkers.clear();
}

/// Derives the visible array values from the store items under [parent].
List<Object?> _rootSequenceValues(Doc doc, ItemParent parent) {
  final values = <Object?>[];
  for (final item in parent.items()) {
    if (item.deleted || !item.countable) {
      continue;
    }
    switch (item.content) {
      case ContentType():
        values.add(_liveNestedType(doc, item));
      case final content:
        values.addAll(content.content);
    }
  }
  return values;
}

/// Inserts [values] into the store-backed array [type] at visible [index].
void _insertRootSequenceValues(
  Transaction transaction,
  SharedType type,
  int index,
  List<Object?> values,
) {
  final parent = _storeParentFor(type);
  if (parent == null || values.isEmpty) {
    return;
  }
  final document = transaction.doc;
  final target = _LocalTextIntegrationTarget(transaction);
  var insertionIndex = index;
  for (final run in _sequenceContentRuns(values)) {
    final origin = _sequencePositionAt(parent, insertionIndex - 1)?.lastId;
    final rightOrigin = _sequencePositionAt(parent, insertionIndex)?.firstId;
    _cleanItemBoundaries(
      document.store,
      origin: origin,
      rightOrigin: rightOrigin,
    );
    final item = Item(
      id: Id(
        client: document.clientId,
        clock: document.store.getClock(document.clientId),
      ),
      left: origin == null ? null : document.store.itemContaining(origin),
      origin: origin,
      right: rightOrigin == null
          ? null
          : document.store.itemContaining(rightOrigin),
      rightOrigin: rightOrigin,
      parent: parent,
      content: run.content,
    );
    item.integrate(target);
    if (item.content is ContentType) {
      _integrateNestedValue(transaction, item);
    }
    insertionIndex += run.textLength;
  }
}

/// Deletes [length] elements from the store-backed array [type] at [index].
void _deleteRootSequenceRange(
  Transaction transaction,
  SharedType type,
  int index,
  int length,
) {
  final parent = _storeParentFor(type);
  if (parent == null || length == 0) {
    return;
  }
  final document = transaction.doc;
  final target = _LocalTextIntegrationTarget(transaction);
  final deleteEnd = index + length;
  var sequenceIndex = 0;
  for (final item in parent.items()) {
    final itemLength = _itemSequenceLength(item);
    if (itemLength == 0) {
      continue;
    }
    final itemEnd = sequenceIndex + itemLength;
    final itemDeleteStart = max(index, sequenceIndex);
    final itemDeleteEnd = min(deleteEnd, itemEnd);
    if (itemDeleteStart < itemDeleteEnd) {
      final range = IdRange(
        start: Clock(item.id.clock.value + (itemDeleteStart - sequenceIndex)),
        length: itemDeleteEnd - itemDeleteStart,
      );
      for (final struct in document.store.structsWithSplitting(
        client: item.id.client,
        range: range,
      )) {
        if (struct is Item && !struct.deleted) {
          struct.delete(target);
        }
      }
    }
    sequenceIndex = itemEnd;
    if (sequenceIndex >= deleteEnd) {
      return;
    }
  }
}

/// Groups [values] into integration runs: consecutive non-shared-type values
/// collapse into one [ContentAny]; each nested [SharedType] becomes a
/// [ContentType].
List<_TextContentRun> _sequenceContentRuns(List<Object?> values) {
  final runs = <_TextContentRun>[];
  var index = 0;
  while (index < values.length) {
    final value = values[index];
    if (value is SharedType) {
      runs.add(
        _TextContentRun(content: ContentType(value), textLength: 1),
      );
      index += 1;
      continue;
    }
    final batch = <Object?>[];
    while (index < values.length && values[index] is! SharedType) {
      batch.add(values[index]);
      index += 1;
    }
    runs.add(
      _TextContentRun(
        content: ContentAny.fromObjects(batch),
        textLength: batch.length,
      ),
    );
  }
  return runs;
}

/// Visible length of [item] within an array (one clock unit per element).
int _itemSequenceLength(Item item) {
  if (item.deleted || !item.countable) {
    return 0;
  }
  return item.length;
}

/// Maps a visible array [index] to a store clock position under [parent].
_TextClockPosition? _sequencePositionAt(ItemParent parent, int index) {
  if (index < 0) {
    return null;
  }
  var remaining = index;
  for (final item in parent.items()) {
    final itemLength = _itemSequenceLength(item);
    if (itemLength == 0) {
      continue;
    }
    if (remaining < itemLength) {
      return _TextClockPosition(
        item: item,
        clockOffset: remaining,
        clockLength: 1,
      );
    }
    remaining -= itemLength;
  }
  return null;
}

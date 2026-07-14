part of 'doc.dart';

/// Whether [type]'s map attributes are backed by the struct store (an
/// integrated root map). Detached maps — and the attribute side of non-map
/// types — keep the in-memory clock-based model for now.
bool _isStoreBackedMap(SharedType type) =>
    type.kind == SharedTypeKind.map && _storeParentFor(type) != null;

/// Rebuilds a store-backed map's in-memory `_attrs`/`_children` cache from the
/// struct store. The store is the single source of truth; the cache is derived.
void _syncMapFromStoreIfNeeded(SharedType type) {
  if (type.kind != SharedTypeKind.map) {
    return;
  }
  final parent = _storeParentFor(type);
  if (parent == null) {
    return;
  }

  // Current visible value per key, in deterministic first-set key order.
  final next = <String, Object?>{};
  for (final key in parent.subKeys.toList(growable: false)) {
    final item = parent.currentFor(key);
    if (item == null || item.deleted) {
      continue;
    }
    next[key] = _mapItemValue(type.doc!, item);
  }

  // Detach children and drop entries for keys that are gone.
  for (final key in type._attrs.keys.toList(growable: false)) {
    if (!next.containsKey(key)) {
      type._detachAttributeChild(key, type._attrs[key]!.value);
      type._attrs.remove(key);
    }
  }

  // Apply current values, (re)binding nested children as needed.
  for (final entry in next.entries) {
    final existing = type._attrs[entry.key];
    if (existing != null && _sameTextValue(existing.value, entry.value)) {
      continue;
    }
    if (existing != null) {
      type._detachAttributeChild(entry.key, existing.value);
    }
    type._attrs[entry.key] = _AttributeEntry(value: entry.value, clock: 0);
    type._bindAttributeChild(entry.key, entry.value);
  }
}

/// The visible value carried by a map attribute [item].
Object? _mapItemValue(Doc doc, Item item) {
  final content = item.content;
  if (content is ContentType) {
    return _liveNestedType(doc, item);
  }
  final values = content.content;
  return values.isEmpty ? null : values.first;
}

/// Sets a store-backed map attribute by appending a new `parentSub` item that
/// supersedes (and deletes) the prior current item — structural last-writer
/// resolution, the same mechanism the integration engine already uses.
void _setRootMapAttr(
  Transaction transaction,
  SharedType type,
  String key,
  Object? value,
) {
  final parent = _storeParentFor(type);
  if (parent == null) {
    return;
  }
  final document = transaction.doc;
  final target = _LocalTextIntegrationTarget(transaction);
  final current = parent.currentFor(key);
  final origin = current?.lastId;
  final item = Item(
    id: Id(
      client: document.clientId,
      clock: document.store.getClock(document.clientId),
    ),
    left: origin == null ? null : document.store.itemContaining(origin),
    origin: origin,
    parent: parent,
    parentSub: key,
    content: value is SharedType
        ? ContentType(value)
        : ContentAny.fromObjects(<Object?>[value]),
  );
  item.integrate(target);
  if (item.content is ContentType) {
    _integrateNestedValue(transaction, item);
  }
}

/// Deletes a store-backed map attribute by tombstoning its current item.
bool _deleteRootMapAttr(
  Transaction transaction,
  SharedType type,
  String key,
) {
  final parent = _storeParentFor(type);
  if (parent == null) {
    return false;
  }
  final current = parent.currentFor(key);
  if (current == null || current.deleted) {
    return false;
  }
  current.delete(_LocalTextIntegrationTarget(transaction));
  return true;
}

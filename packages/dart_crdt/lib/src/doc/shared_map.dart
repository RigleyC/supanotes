part of 'doc.dart';

final class _AttributeEntry {
  const _AttributeEntry({
    required this.value,
    required this.clock,
  });

  final Object? value;
  final int clock;
}

/// Attribute and map-like APIs for [SharedType].
extension SharedTypeAttributes on SharedType {
  /// Number of currently visible attributes.
  int get attrSize {
    _syncMapFromStoreIfNeeded(this);
    return _attrs.length;
  }

  /// Sets [key] to [value] using last-writer-wins conflict ordering.
  ///
  /// For an integrated root map the value is stored as a `parentSub` item and
  /// conflicts resolve structurally by item-id order, so [clock] is advisory. A
  /// detached map keeps the in-memory clock-based resolution.
  void setAttr(String key, Object? value, {int? clock}) {
    _checkAttributeKey(key);
    if (_isStoreBackedMap(this)) {
      _validateAttributeValue(value);
      doc!.transact((transaction) {
        _setRootMapAttr(transaction, this, key, value);
        _syncMapFromStoreIfNeeded(this);
        markChanged(key);
      });
      return;
    }
    final resolvedClock = clock ?? _nextAttributeClock();
    _recordAttributeClock(resolvedClock);
    final deleteClock = _attrDeleteClocks[key];
    if (deleteClock != null && resolvedClock < deleteClock) {
      return;
    }
    final current = _attrs[key];
    if (current != null && resolvedClock < current.clock) {
      return;
    }

    _detachAttributeChild(key, current?.value);
    _validateAttributeValue(value);
    _attrs[key] = _AttributeEntry(value: value, clock: resolvedClock);
    _attrDeleteClocks.remove(key);
    _bindAttributeChild(key, value);
    markChanged(key);
  }

  /// Returns the value for [key], or `null` when absent.
  Object? getAttr(String key) {
    _checkAttributeKey(key);
    _syncMapFromStoreIfNeeded(this);
    return _attrs[key]?.value;
  }

  /// Returns whether [key] has a visible value.
  bool hasAttr(String key) {
    _checkAttributeKey(key);
    _syncMapFromStoreIfNeeded(this);
    return _attrs.containsKey(key);
  }

  /// Deletes [key] when this operation wins conflict ordering.
  bool deleteAttr(String key, {int? clock}) {
    _checkAttributeKey(key);
    if (_isStoreBackedMap(this)) {
      final current = _storeParentFor(this)!.currentFor(key);
      if (current == null || current.deleted) {
        return false;
      }
      doc!.transact((transaction) {
        _deleteRootMapAttr(transaction, this, key);
        _syncMapFromStoreIfNeeded(this);
        markChanged(key);
      });
      return true;
    }
    final current = _attrs[key];
    final resolvedClock = clock ?? _nextAttributeClock();
    _recordAttributeClock(resolvedClock);
    final deleteClock = _attrDeleteClocks[key];
    if (deleteClock != null && resolvedClock < deleteClock) {
      return false;
    }
    if (current == null) {
      _attrDeleteClocks[key] = resolvedClock;
      return false;
    }
    if (resolvedClock < current.clock) {
      return false;
    }

    _attrs.remove(key);
    _attrDeleteClocks[key] = resolvedClock;
    _detachAttributeChild(key, current.value);
    markChanged(key);
    return true;
  }

  /// Deletes all currently visible attributes.
  void clearAttrs() {
    _syncMapFromStoreIfNeeded(this);
    if (_attrs.isEmpty) {
      return;
    }
    final keys = List<String>.unmodifiable(_attrs.keys);
    for (final key in keys) {
      deleteAttr(key);
    }
  }

  /// Returns an immutable snapshot of all attributes.
  Map<String, Object?> getAttrs() {
    _syncMapFromStoreIfNeeded(this);
    return Map<String, Object?>.unmodifiable(
      _attrs.map((key, entry) => MapEntry(key, entry.value)),
    );
  }

  /// Invokes [visitor] for each attribute in insertion order.
  void forEachAttr(void Function(String key, Object? value) visitor) {
    final snapshot = attrEntries;
    for (final entry in snapshot) {
      visitor(entry.key, entry.value);
    }
  }

  /// Attribute keys in stable insertion order.
  Iterable<String> get attrKeys {
    _syncMapFromStoreIfNeeded(this);
    return List<String>.unmodifiable(_attrs.keys);
  }

  /// Attribute values in stable insertion order.
  Iterable<Object?> get attrValues {
    _syncMapFromStoreIfNeeded(this);
    return List<Object?>.unmodifiable(
      _attrs.values.map((entry) => entry.value),
    );
  }

  /// Attribute entries in stable insertion order.
  Iterable<MapEntry<String, Object?>> get attrEntries {
    _syncMapFromStoreIfNeeded(this);
    return List<MapEntry<String, Object?>>.unmodifiable(
      _attrs.entries.map((entry) => MapEntry(entry.key, entry.value.value)),
    );
  }

  int _nextAttributeClock() {
    _attrClock += 1;
    return _attrClock;
  }

  void _recordAttributeClock(int clock) {
    if (clock > _attrClock) {
      _attrClock = clock;
    }
  }

  void _bindAttributeChild(String key, Object? value) {
    if (value is SharedType) {
      value._attachToParent(this, key);
      _children[key] = value;
    }
  }

  void _detachAttributeChild(String key, Object? value) {
    if (value is SharedType && identical(_children[key], value)) {
      _children.remove(key);
      value._detachFromParent(this, key);
    }
  }
}

String _checkAttributeKey(String key) {
  if (key.isEmpty) {
    throw ArgumentError.value(key, 'key', 'must not be empty');
  }
  return key;
}

void _validateAttributeValue(Object? value) {
  if (value is SharedType && value.parent != null) {
    throw StateError('Shared type is already integrated elsewhere.');
  }
}

void _copyAttributesInto(SharedType source, SharedType target) {
  for (final entry in source._attrs.entries) {
    final value = entry.value.value;
    target.setAttr(
      entry.key,
      value is SharedType ? value.copy() : value,
      clock: entry.value.clock,
    );
  }
}

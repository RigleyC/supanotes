part of 'doc.dart';

/// Registry access for nested store-backed shared types, kept out of [Doc]
/// itself to keep that file focused.
extension DocNestedTypeAccess on Doc {
  /// Returns the item parent for the nested type defined by [id], creating it
  /// lazily so child items can resolve their parent before the defining
  /// `ContentType` item has been integrated.
  ItemParent itemParentForItemId(Id id) {
    return _itemParentsByItemId.putIfAbsent(
      id,
      () => ItemParent(key: '', definingItemId: id),
    );
  }

  /// Live nested shared type bound to the `ContentType` item [id], or `null`.
  SharedType? sharedTypeForItemId(Id id) => _sharedTypeByItemId[id];

  /// Registers the live nested shared type [type] for `ContentType` item [id].
  void registerSharedTypeForItemId(Id id, SharedType type) {
    _sharedTypeByItemId[id] = type;
  }

  /// Returns the store item parent backing [type] (root or nested), or `null`
  /// when [type] is not store-backed. Used by relative-position resolution.
  ItemParent? storeParentForType(SharedType type) => _storeParentFor(type);

  /// Materializes (and binds) the live nested type defined by `ContentType`
  /// [item]. Used by relative-position resolution.
  SharedType liveNestedTypeForItem(Item item) => _liveNestedType(this, item);
}

/// Emits [SharedTypeEvent]s for the types changed during [transaction].
///
/// Direct changes from local mutations carry their visible keys/indices.
/// Store-driven changes (notably remote applies) reach the type only through
/// its parent, so those are resolved and emitted unless a local mutation
/// already covered the same type.
void _emitSharedTypeEvents(
  Transaction transaction,
  void Function(void Function()) captureError,
) {
  final emitted = <SharedType>{};
  for (final entry in transaction._changed.entries) {
    final target = entry.key;
    if (target is SharedType) {
      emitted.add(target);
      final event = SharedTypeEvent(
        target: target,
        keys: entry.value,
        transaction: transaction,
      );
      captureError(() => target._emitEvent(event));
    }
  }
  for (final entry in transaction._changed.entries) {
    final target = entry.key;
    if (target is ItemParent) {
      final type = _typeForItemParent(transaction.doc, target);
      if (type == null || emitted.contains(type)) {
        continue;
      }
      emitted.add(type);
      final event = SharedTypeEvent(
        target: type,
        keys: entry.value,
        transaction: transaction,
      );
      captureError(() => type._emitEvent(event));
    }
  }
}

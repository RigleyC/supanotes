part of 'undo_manager.dart';

/// Insert/delete id-set pair captured on an undo or redo stack.
final class StackItem {
  /// Creates an empty stack item.
  StackItem({Map<Object, Object?>? meta})
      : _inserts = IdSet(),
        _deletes = IdSet(),
        meta = LinkedHashMap<Object, Object?>.of(
          meta ?? const <Object, Object?>{},
        );

  /// Creates a stack item with defensive copies of [inserts] and [deletes].
  StackItem.fromSets(
    IdSet inserts,
    IdSet deletes, {
    Map<Object, Object?>? meta,
  })  : _inserts = _copyIdSet(inserts),
        _deletes = _copyIdSet(deletes),
        meta = LinkedHashMap<Object, Object?>.of(
          meta ?? const <Object, Object?>{},
        );

  IdSet _inserts;
  IdSet _deletes;

  /// User metadata associated with this stack item.
  final Map<Object, Object?> meta;

  /// Inserted ids captured by this item.
  IdSet get inserts => _copyIdSet(_inserts);

  /// Deleted ids captured by this item.
  IdSet get deletes => _copyIdSet(_deletes);

  /// Whether no insert or delete ranges are captured.
  bool get isEmpty => _inserts.isEmpty && _deletes.isEmpty;

  void _merge(IdSet inserts, IdSet deletes) {
    _inserts = _inserts.merged(inserts);
    _deletes = _deletes.merged(deletes);
  }
}

IdSet _copyIdSet(IdSet source) {
  final copy = IdSet();
  source.insertInto(copy);
  return copy;
}

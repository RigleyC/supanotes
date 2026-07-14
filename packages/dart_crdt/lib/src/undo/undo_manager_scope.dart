part of 'undo_manager.dart';

Doc _docFromScope(Object? scope) {
  for (final entry in _normalizeScope(scope)) {
    if (entry is Doc) {
      return entry;
    }
    if (entry is SharedType && entry.doc != null) {
      return entry.doc!;
    }
  }
  throw ArgumentError.value(
    scope,
    'scope',
    'must include a document or integrated shared type when doc is omitted',
  );
}

List<Object> _normalizeScope(Object? scope) {
  if (scope == null) {
    return const <Object>[];
  }
  if (scope is Doc || scope is SharedType) {
    return <Object>[scope];
  }
  if (scope is Iterable) {
    final values = <Object>[];
    for (final entry in scope) {
      if (entry is! Doc && entry is! SharedType) {
        throw ArgumentError.value(
          entry,
          'scope',
          'must contain only documents or shared types',
        );
      }
      values.add(entry as Object);
    }
    return List<Object>.unmodifiable(values);
  }
  throw ArgumentError.value(
    scope,
    'scope',
    'must be a document, shared type, iterable scope, or null',
  );
}

bool _isSameOrDescendant(SharedType type, SharedType ancestor) {
  SharedType? current = type;
  while (current != null) {
    if (identical(current, ancestor)) {
      return true;
    }
    current = current.parent;
  }
  return false;
}

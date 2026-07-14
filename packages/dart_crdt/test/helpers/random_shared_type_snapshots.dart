part of 'random_shared_type_operations.dart';

/// Stable visible snapshot for shared array convergence checks.
String sequenceConvergenceSnapshot(Doc doc, {String rootName = 'items'}) {
  final array = doc.get(rootName, SharedTypeKind.array);
  return array.toArray().map(_describeSequenceValue).join('|');
}

/// Stable visible snapshot for shared map convergence checks.
String mapConvergenceSnapshot(Doc doc, {String rootName = 'attrs'}) {
  return _attrsSnapshot(doc.get(rootName));
}

/// Stable visible snapshot for shared text convergence checks.
String textConvergenceSnapshot(Doc doc, {String rootName = 'body'}) {
  final text = doc.get(rootName, SharedTypeKind.text);
  return '${jsonEncode(text.toDelta().toJson())}|${_attrsSnapshot(text)}';
}

String _describeSequenceValue(Object? value) {
  if (value is SharedType) {
    return 'nested:${value.getAttr('id')}:${value.getAttr('title')}';
  }
  return '$value';
}

String _attrsSnapshot(SharedType type) {
  final entries = type.getAttrs().entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return entries.map((entry) {
    final value = entry.value;
    if (value is SharedType) {
      return '${entry.key}=nested:${value.getAttr('id')}';
    }
    return '${entry.key}=$value';
  }).join('|');
}

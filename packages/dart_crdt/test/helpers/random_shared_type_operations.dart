import 'dart:convert';

import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/delta/delta_operation.dart';
import 'package:dart_crdt/src/doc/doc.dart';

import 'random_convergence_harness.dart';

part 'random_shared_type_snapshots.dart';

/// Random operation generator for shared array convergence scenarios.
RandomOperationFactory<Doc> randomSequenceOperations({
  String rootName = 'items',
}) {
  return (context) {
    if (context.operationIndex % 3 == 2) {
      final target = context.random.nextInt(context.operationIndex + 1);
      return sequenceDeleteOperation(rootName: rootName, id: 's$target');
    }
    return sequenceInsertOperation(
      rootName: rootName,
      id: 's${context.operationIndex}',
      nested: context.operationIndex % 5 == 0,
    );
  };
}

/// Random operation generator for shared map convergence scenarios.
RandomOperationFactory<Doc> randomMapOperations({
  String rootName = 'attrs',
}) {
  return (context) {
    final key = 'k${context.random.nextInt(5)}';
    final clock = context.operationIndex + 2;
    if (context.operationIndex % 4 == 3) {
      return mapDeleteOperation(rootName: rootName, key: key, clock: clock);
    }
    return mapSetOperation(
      rootName: rootName,
      key: key,
      valueId: 'm${context.operationIndex}-${context.originIndex}',
      clock: clock,
      nested: context.operationIndex % 6 == 0,
    );
  };
}

/// Random operation generator for shared text convergence scenarios.
RandomOperationFactory<Doc> randomTextOperations({
  String rootName = 'body',
}) {
  return (context) {
    if (context.operationIndex % 3 == 2) {
      return textDeleteOperation(
        rootName: rootName,
        token: context.random.nextInt(context.operationIndex + 1),
      );
    }
    return textInsertOperation(
      rootName: rootName,
      token: context.operationIndex,
      origin: context.originIndex,
    );
  };
}

/// Creates an ordered, idempotent shared array insert operation.
RandomConvergenceOperation<Doc> sequenceInsertOperation({
  required String id,
  String rootName = 'items',
  bool nested = false,
}) {
  final kind = nested ? 'nested' : 'scalar';
  return RandomConvergenceOperation<Doc>(
    label: 'array insert $kind:$id',
    apply: (doc) {
      final array = doc.get(rootName, SharedTypeKind.array);
      _insertSequenceValue(array, id: id, nested: nested);
    },
  );
}

/// Creates an idempotent shared array delete operation.
RandomConvergenceOperation<Doc> sequenceDeleteOperation({
  required String id,
  String rootName = 'items',
}) {
  return RandomConvergenceOperation<Doc>(
    label: 'array delete:$id',
    apply: (doc) {
      final array = doc.get(rootName, SharedTypeKind.array);
      array.setAttr(_deletedKey(id), true);
      _removeSequenceValue(array, id);
    },
  );
}

/// Creates a deterministic shared map set operation.
RandomConvergenceOperation<Doc> mapSetOperation({
  required String key,
  required String valueId,
  required int clock,
  String rootName = 'attrs',
  bool nested = false,
}) {
  final kind = nested ? 'nested' : 'scalar';
  return RandomConvergenceOperation<Doc>(
    label: 'map set $kind:$key@$clock',
    apply: (doc) {
      final map = doc.get(rootName);
      final value = nested ? _newNestedMap(valueId) : 'value:$valueId';
      map.setAttr(key, value, clock: clock);
    },
  );
}

/// Creates a deterministic shared map delete operation.
RandomConvergenceOperation<Doc> mapDeleteOperation({
  required String key,
  required int clock,
  String rootName = 'attrs',
}) {
  return RandomConvergenceOperation<Doc>(
    label: 'map delete:$key@$clock',
    apply: (doc) => doc.get(rootName).deleteAttr(key, clock: clock),
  );
}

/// Creates an ordered, idempotent shared text insert operation.
RandomConvergenceOperation<Doc> textInsertOperation({
  required int token,
  required int origin,
  String rootName = 'body',
}) {
  return RandomConvergenceOperation<Doc>(
    label: 'text insert:$token',
    apply: (doc) {
      final text = doc.get(rootName, SharedTypeKind.text);
      _insertTextToken(text, token: token, origin: origin);
    },
  );
}

/// Creates an idempotent shared text delete operation.
RandomConvergenceOperation<Doc> textDeleteOperation({
  required int token,
  String rootName = 'body',
}) {
  return RandomConvergenceOperation<Doc>(
    label: 'text delete:$token',
    apply: (doc) {
      final text = doc.get(rootName, SharedTypeKind.text);
      text.setAttr(_deletedKey('$token'), true);
      _removeTextToken(text, token);
    },
  );
}

void _insertSequenceValue(
  SharedType array, {
  required String id,
  required bool nested,
}) {
  if (array.hasAttr(_deletedKey(id)) || _sequenceIndexOf(array, id) >= 0) {
    return;
  }
  final value = nested ? _newNestedMap(id) : 'item:$id';
  var index = 0;
  final values = array.toArray();
  while (index < values.length &&
      _sequenceValueId(values[index]).compareTo(id) < 0) {
    index += 1;
  }
  array.insert(index, value);
}

void _removeSequenceValue(SharedType array, String id) {
  for (var index = array.length - 1; index >= 0; index -= 1) {
    if (_sequenceValueId(array.get(index)) == id) {
      array.delete(index);
    }
  }
}

int _sequenceIndexOf(SharedType array, String id) {
  for (var index = 0; index < array.length; index += 1) {
    if (_sequenceValueId(array.get(index)) == id) {
      return index;
    }
  }
  return -1;
}

void _insertTextToken(
  SharedType text, {
  required int token,
  required int origin,
}) {
  if (text.hasAttr(_deletedKey('$token'))) {
    return;
  }
  final codePoint = _tokenCodePoint(token);
  final runes = text.toPlainText().runes.toList(growable: false);
  if (runes.contains(codePoint)) {
    return;
  }
  var index = 0;
  while (index < runes.length && runes[index] < codePoint) {
    index += 1;
  }
  text.insertText(
    index,
    String.fromCharCode(codePoint),
    attributes: DeltaAttributes.fromJson({'origin': origin, 'token': token}),
  );
}

void _removeTextToken(SharedType text, int token) {
  final runes = text.toPlainText().runes.toList(growable: false);
  final index = runes.indexOf(_tokenCodePoint(token));
  if (index >= 0) {
    text.deleteText(index, 1);
  }
}

SharedType _newNestedMap(String id) {
  return SharedType(kind: SharedTypeKind.map, name: 'nested-$id')
    ..setAttr('id', id)
    ..setAttr('title', 'Nested $id');
}

String _sequenceValueId(Object? value) {
  if (value is SharedType) {
    return '${value.getAttr('id')}';
  }
  final text = '$value';
  return text.startsWith('item:') ? text.substring(5) : text;
}

String _deletedKey(String id) => 'deleted:$id';

int _tokenCodePoint(int token) => 0xE000 + token;

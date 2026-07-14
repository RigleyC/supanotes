part of 'serialized_fixtures_test.dart';

List<Map<String, Object?>> _fixtureCases() {
  return [
    for (final line in File(_fixturePath).readAsLinesSync())
      if (line.trim().isNotEmpty) _objectMap(jsonDecode(line), _fixturePath),
  ];
}

List<int> _payload(
  Map<String, Object?> fixtureCase,
  String direction,
  String format,
) {
  for (final entry in _mapList(fixtureCase, 'roundTrips')) {
    if (entry['direction'] == direction && entry['format'] == format) {
      return _decodeHex(_stringField(entry, 'payloadHex'));
    }
  }
  throw StateError(
    'Missing $direction $format fixture for ${fixtureCase['id']}.',
  );
}

List<int> _contentRefs(Doc doc) {
  final refs = <int>[];
  for (final client in doc.store.clients) {
    for (final struct in doc.store.structsFor(client)) {
      if (struct is Item) {
        refs.add(struct.content.ref);
      }
    }
  }
  return refs;
}

int _deletedCount(Doc doc) {
  var count = 0;
  for (final client in doc.store.clients) {
    for (final struct in doc.store.structsFor(client)) {
      if (struct.deleted) {
        count += 1;
      }
    }
  }
  return count;
}

Map<String, int> _jsonState(StateVector state) {
  return {
    for (final entry in state.entries) '${entry.key.value}': entry.value.value,
  };
}

List<int> _clients(Iterable<ClientId> clients) {
  return [for (final client in clients) client.value];
}

List<int> _decodeHex(String value) {
  if (value.length.isOdd) {
    throw StateError('Odd hex payload length.');
  }
  return [
    for (var index = 0; index < value.length; index += 2)
      int.parse(value.substring(index, index + 2), radix: 16),
  ];
}

String _hex(List<int> bytes) {
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

List<String> _sortedStrings(Iterable<String> values) {
  return (values.toList()..sort()).toList(growable: false);
}

List<int> _intList(Map<String, Object?> value, String key) {
  return [
    for (final item in _objectList(value[key], key))
      if (item is int) item else throw StateError('$key must contain ints.'),
  ];
}

List<String> _stringList(Map<String, Object?> value, String key) {
  return [
    for (final item in _objectList(value[key], key))
      if (item is String)
        item
      else
        throw StateError('$key must contain strings.'),
  ];
}

Map<String, int> _intMap(Map<String, Object?> value, String key) {
  final result = <String, int>{};
  for (final entry in _mapField(value, key).entries) {
    final entryValue = entry.value;
    if (entryValue is! int) {
      throw StateError('$key must contain int values.');
    }
    result[entry.key] = entryValue;
  }
  return result;
}

List<int> _encodeIdMap(IdMap map) {
  final writer = ByteWriter();
  IdMapEncoderV2.write(writer, map);
  return writer.toBytes();
}

Map<String, Object?> _mapField(Map<String, Object?> value, String key) {
  return _objectMap(value[key], key);
}

List<Map<String, Object?>> _mapList(Map<String, Object?> value, String key) {
  return [
    for (final item in _objectList(value[key], key)) _objectMap(item, key),
  ];
}

List<Object?> _objectList(Object? value, String context) {
  if (value is List<Object?>) {
    return value;
  }
  throw StateError('$context must be a list.');
}

Map<String, Object?> _objectMap(Object? value, String context) {
  if (value is Map<String, Object?>) {
    return value;
  }
  throw StateError('$context must be an object.');
}

String _stringField(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is String) {
    return field;
  }
  throw StateError('$key must be a string.');
}

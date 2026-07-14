import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _fixtureRoot = 'test/fixtures/compat';
const _requiredCategories = {
  'empty-docs',
  'nested-docs',
  'arrays',
  'maps',
  'text',
  'rich-text-formats',
  'xml-tree-content',
  'subdocs',
  'binary-content',
  'embeds',
  'json',
  'pending-updates',
  'deletes',
  'gc-disabled-snapshots',
  'attribution-maps',
};

const _serializedFormats = {
  'update-v1',
  'update-v2',
  'state-vector',
  'snapshot',
  'relative-position',
  'id-map',
  'content-map',
};

const _roundTripDirections = {
  'reference-to-dart',
  'dart-to-reference',
};

final _forbiddenReference = RegExp('y' 'js', caseSensitive: false);
final _hexPattern = RegExp(r'^(?:[0-9a-f]{2})+$');

void main() {
  test('validates the neutral compatibility fixture manifest', () {
    final schema = _jsonMap('$_fixtureRoot/manifest.schema.json');
    final manifest = _jsonMap('$_fixtureRoot/manifest.json');
    final caseFile = _stringField(manifest, 'caseFile');
    final cases = _jsonLines('$_fixtureRoot/$caseFile');

    _expectRequiredKeys(
      manifest,
      _stringList(schema, 'requiredTopLevelKeys').toSet(),
    );
    _expectNoForbiddenReferences(Directory(_fixtureRoot));
    expect(manifest['schemaVersion'], schema['version']);
    expect(
      _stringList(manifest, 'requiredCategories').toSet(),
      _requiredCategories,
    );
    expect(
      _stringList(manifest, 'serializedFormats').toSet(),
      _serializedFormats,
    );
    expect(
      _stringList(manifest, 'roundTripDirections').toSet(),
      _roundTripDirections,
    );

    _expectManifestCases(manifest, cases);
    for (final fixtureCase in cases) {
      _expectFixtureCase(
        fixtureCase,
        _stringList(schema, 'caseRequiredKeys').toSet(),
        _stringList(schema, 'roundTripRequiredKeys').toSet(),
      );
    }
  });
}

void _expectManifestCases(
  Map<String, Object?> manifest,
  List<Map<String, Object?>> cases,
) {
  final manifestCases = _mapList(manifest, 'cases');
  expect(manifestCases.length, cases.length);
  expect(
    cases.map((fixtureCase) => _stringField(fixtureCase, 'category')).toSet(),
    _requiredCategories,
  );

  final ids = <String>{};
  for (final fixtureCase in cases) {
    final id = _stringField(fixtureCase, 'id');
    expect(ids.add(id), isTrue, reason: 'Duplicate fixture case id: $id');
    expect(
      manifestCases.any(
        (entry) =>
            entry['id'] == id &&
            entry['category'] == _stringField(fixtureCase, 'category'),
      ),
      isTrue,
      reason: 'Manifest does not list fixture case $id.',
    );
  }
}

void _expectFixtureCase(
  Map<String, Object?> fixtureCase,
  Set<String> caseRequiredKeys,
  Set<String> roundTripRequiredKeys,
) {
  _expectRequiredKeys(fixtureCase, caseRequiredKeys);
  expect(_stringList(fixtureCase, 'formats').toSet(), _serializedFormats);

  final seenPairs = <String>{};
  for (final roundTrip in _mapList(fixtureCase, 'roundTrips')) {
    _expectRequiredKeys(roundTrip, roundTripRequiredKeys);
    final direction = _stringField(roundTrip, 'direction');
    final format = _stringField(roundTrip, 'format');
    final payloadHex = _stringField(roundTrip, 'payloadHex');

    expect(_roundTripDirections, contains(direction));
    expect(_serializedFormats, contains(format));
    expect(_hexPattern.hasMatch(payloadHex), isTrue);
    expect(
      seenPairs.add('$direction:$format'),
      isTrue,
      reason: 'Duplicate round-trip entry in ${fixtureCase['id']}.',
    );
  }

  for (final direction in _roundTripDirections) {
    for (final format in _serializedFormats) {
      expect(seenPairs, contains('$direction:$format'));
    }
  }
}

void _expectRequiredKeys(Map<String, Object?> value, Set<String> keys) {
  for (final key in keys) {
    expect(value, contains(key));
  }
}

void _expectNoForbiddenReferences(Directory directory) {
  for (final file in directory.listSync(recursive: true).whereType<File>()) {
    final relativePath = file.path.replaceAll(r'\', '/');
    expect(_forbiddenReference.hasMatch(relativePath), isFalse);
    expect(_forbiddenReference.hasMatch(file.readAsStringSync()), isFalse);
  }
}

Map<String, Object?> _jsonMap(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync());
  if (decoded is Map<String, Object?>) {
    return decoded;
  }
  throw StateError('Expected JSON object in $path.');
}

List<Map<String, Object?>> _jsonLines(String path) {
  final lines = File(path).readAsLinesSync();
  expect(lines, isNotEmpty);
  return [
    for (final line in lines)
      if (line.trim().isNotEmpty) _lineMap(line, path),
  ];
}

Map<String, Object?> _lineMap(String line, String path) {
  final decoded = jsonDecode(line);
  if (decoded is Map<String, Object?>) {
    return decoded;
  }
  throw StateError('Expected JSON object line in $path.');
}

String _stringField(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is String) {
    return field;
  }
  throw StateError('Expected string field $key.');
}

List<String> _stringList(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is List<Object?> && field.every((item) => item is String)) {
    return field.cast<String>();
  }
  throw StateError('Expected string list field $key.');
}

List<Map<String, Object?>> _mapList(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is List<Object?>) {
    return [
      for (final item in field)
        if (item is Map<String, Object?>) item,
    ];
  }
  throw StateError('Expected object list field $key.');
}

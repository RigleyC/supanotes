import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _fixtureRoot = 'test/fixtures/compat';
const _advancedCategories = {
  'rich-text-formats',
  'xml-tree-content',
  'subdocs',
  'pending-updates',
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
const _directions = {'reference-to-dart', 'dart-to-reference'};

void main() {
  group('advanced compatibility fixture regressions', () {
    test('advanced fixture categories include every format and direction', () {
      final manifest = _jsonMap('$_fixtureRoot/manifest.json');
      final caseFile = _stringField(manifest, 'caseFile');
      final cases = _jsonLines('$_fixtureRoot/$caseFile');
      final byCategory = {
        for (final fixtureCase in cases)
          _stringField(fixtureCase, 'category'): fixtureCase,
      };

      expect(
        _stringList(manifest, 'requiredCategories').toSet(),
        containsAll(_advancedCategories),
      );
      expect(
        _stringList(manifest, 'serializedFormats').toSet(),
        containsAll(_serializedFormats),
      );

      for (final category in _advancedCategories) {
        final fixtureCase = byCategory[category];
        expect(fixtureCase, isNotNull, reason: 'Missing $category fixture.');
        _expectCompleteRoundTrips(fixtureCase!);
      }
    });
  });
}

void _expectCompleteRoundTrips(Map<String, Object?> fixtureCase) {
  expect(_stringList(fixtureCase, 'formats').toSet(), _serializedFormats);
  final pairs = {
    for (final roundTrip in _mapList(fixtureCase, 'roundTrips'))
      '${_stringField(roundTrip, 'direction')}:'
          '${_stringField(roundTrip, 'format')}',
  };
  for (final direction in _directions) {
    for (final format in _serializedFormats) {
      expect(
        pairs,
        contains('$direction:$format'),
        reason: 'Missing $direction $format for ${fixtureCase['id']}.',
      );
    }
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
  return [
    for (final line in File(path).readAsLinesSync())
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

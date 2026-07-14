import 'dart:convert';
import 'dart:io';

import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/metadata/content_ids.dart';
import 'package:dart_crdt/src/metadata/id_range.dart';
import 'package:dart_crdt/src/metadata/id_set.dart';
import 'package:dart_crdt/src/structs/abstract_struct.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:dart_crdt/src/sync/apply_update.dart';
import 'package:dart_crdt/src/sync/state_update.dart';
import 'package:dart_crdt/src/sync/update_algebra.dart';
import 'package:dart_crdt/src/sync/update_content_ids.dart';
import 'package:dart_crdt/src/sync/update_obfuscation.dart';

/// Encodes a document as an update.
typedef UpdateEncode = List<int> Function(Doc doc);

/// Applies an update to a document.
typedef UpdateApply = void Function(Doc doc, List<int> update);

/// Merges multiple updates.
typedef UpdateMerge = List<int> Function(Iterable<List<int>> updates);

/// Diffs an update against an encoded state vector.
typedef UpdateDiff = List<int> Function(
  List<int> update,
  List<int> stateVector,
);

/// Extracts content ids from an update.
typedef UpdateContentIds = ContentIds Function(List<int> update);

/// Intersects an update with selected content ids.
typedef UpdateIntersect = List<int> Function(
  List<int> update,
  ContentIds ids,
);

/// Obfuscates an update.
typedef UpdateObfuscate = List<int> Function(
  List<int> update, {
  UpdateObfuscationOptions options,
});

/// Version-specific update operations used by regression tests.
final class UpdateVersion {
  /// Creates a version-specific update operation bundle.
  const UpdateVersion({
    required this.name,
    required this.encode,
    required this.apply,
    required this.merge,
    required this.diff,
    required this.contentIds,
    required this.intersect,
    required this.obfuscate,
  });

  /// Fixture and test display name.
  final String name;

  /// Encodes a document.
  final UpdateEncode encode;

  /// Applies an update to a document.
  final UpdateApply apply;

  /// Merges updates.
  final UpdateMerge merge;

  /// Diffs an update against a state vector.
  final UpdateDiff diff;

  /// Extracts update content ids.
  final UpdateContentIds contentIds;

  /// Intersects updates with content ids.
  final UpdateIntersect intersect;

  /// Obfuscates update content.
  final UpdateObfuscate obfuscate;

  /// Reads this version's bytes from the shared update fixture file.
  List<int> fixture(String name) => updateFixture(name, this.name);
}

/// Supported update versions for parity tests.
const updateVersions = <UpdateVersion>[
  UpdateVersion(
    name: 'v1',
    encode: encodeStateAsUpdate,
    apply: applyUpdate,
    merge: mergeUpdates,
    diff: diffUpdate,
    contentIds: createContentIdsFromUpdate,
    intersect: intersectUpdateWithContentIds,
    obfuscate: obfuscateUpdate,
  ),
  UpdateVersion(
    name: 'v2',
    encode: encodeStateAsUpdateV2,
    apply: applyUpdateV2,
    merge: mergeUpdatesV2,
    diff: diffUpdateV2,
    contentIds: createContentIdsFromUpdateV2,
    intersect: intersectUpdateWithContentIdsV2,
    obfuscate: obfuscateUpdateV2,
  ),
];

Map<String, Object?>? _fixtureCache;

/// Reads update bytes from `test/fixtures/compat/updates/regression_cases.json`.
List<int> updateFixture(String caseName, String version) {
  final root = _fixtureCache ??= _readFixtureRoot();
  final cases = root['cases']! as Map<String, Object?>;
  final fixtureCase = cases[caseName] as Map<String, Object?>?;
  if (fixtureCase == null) {
    throw StateError('Missing update fixture "$caseName".');
  }
  final bytes = fixtureCase[version] as List<Object?>?;
  if (bytes == null) {
    throw StateError('Missing update fixture "$caseName" version "$version".');
  }
  return List<int>.unmodifiable(bytes.cast<int>());
}

/// Creates a document with contiguous root content for one client.
Doc docWithContent(int client, List<AbstractContent> contents) {
  final doc = Doc(gc: false, clientId: ClientId(client));
  var clock = 0;
  for (final content in contents) {
    doc.store.add(
      Item(
        id: id(client, clock),
        parent: doc.itemParentForKey('root'),
        content: content,
      ),
    );
    clock += content.length;
  }
  return doc;
}

/// Returns visible and non-visible root item content in item order.
List<AbstractContent> rootContents(Doc doc) {
  return [
    for (final item in doc.itemParentForKey('root').items())
      if (!item.deleted) item.content,
  ];
}

/// Returns visible root strings concatenated in item order.
String rootText(Doc doc) {
  return rootContents(doc)
      .whereType<ContentString>()
      .map((c) => c.value)
      .join();
}

/// Creates an id from integer parts.
Id id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}

/// Creates an id range set from tuple ranges.
IdSet idSet(List<(int client, int start, int length)> ranges) {
  final set = IdSet();
  for (final range in ranges) {
    set.addRange(
      ClientId(range.$1),
      IdRange(start: Clock(range.$2), length: range.$3),
    );
  }
  return set;
}

/// Counts non-overlapping byte-pattern occurrences.
int countBytePattern(List<int> bytes, List<int> pattern) {
  var count = 0;
  for (var index = 0; index <= bytes.length - pattern.length; index += 1) {
    var matches = true;
    for (var offset = 0; offset < pattern.length; offset += 1) {
      if (bytes[index + offset] != pattern[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      count += 1;
      index += pattern.length - 1;
    }
  }
  return count;
}

Map<String, Object?> _readFixtureRoot() {
  final file = File('test/fixtures/compat/updates/regression_cases.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

/// Insert/delete id-map metadata containers.
library;

import 'content_attribute.dart';
import 'content_ids.dart';
import 'id_map.dart';

/// Immutable container for attributed insert and delete maps.
final class ContentMap {
  /// Creates a content map with defensive copies of [inserts] and [deletes].
  factory ContentMap({
    IdMap? inserts,
    IdMap? deletes,
  }) {
    return ContentMap._(
      inserts: _copyIdMap(inserts ?? IdMap()),
      deletes: _copyIdMap(deletes ?? IdMap()),
    );
  }

  const ContentMap._({
    required IdMap inserts,
    required IdMap deletes,
  })  : _inserts = inserts,
        _deletes = deletes;

  /// Creates an empty content map.
  factory ContentMap.empty() => ContentMap();

  /// Creates a content map from [contentIds] and attribution lists.
  factory ContentMap.fromContentIds(
    ContentIds contentIds, {
    Iterable<ContentAttribute> insertAttributes = const <ContentAttribute>[],
    Iterable<ContentAttribute>? deleteAttributes,
  }) {
    return contentIds.toContentMap(
      insertAttributes: insertAttributes,
      deleteAttributes: deleteAttributes,
    );
  }

  final IdMap _inserts;
  final IdMap _deletes;

  /// Inserted content map as a defensive copy.
  IdMap get inserts => _copyIdMap(_inserts);

  /// Deleted content map as a defensive copy.
  IdMap get deletes => _copyIdMap(_deletes);

  /// Whether both branches are empty.
  bool get isEmpty => _inserts.isEmpty && _deletes.isEmpty;

  /// Whether at least one branch contains ranges.
  bool get isNotEmpty => !isEmpty;

  /// Converts this content map to id-only metadata.
  ContentIds toContentIds() {
    return ContentIds(
      inserts: _inserts.toIdSet(),
      deletes: _deletes.toIdSet(),
    );
  }

  /// Returns the union of this map and [other].
  ContentMap merged(ContentMap other) {
    return ContentMap(
      inserts: _inserts.merged(other._inserts),
      deletes: _deletes.merged(other._deletes),
    );
  }

  /// Returns this map with [other] removed.
  ContentMap exclude(ContentMap other) {
    return ContentMap(
      inserts: _inserts.diff(other._inserts),
      deletes: _deletes.diff(other._deletes),
    );
  }

  /// Returns this map with [other] ids removed.
  ContentMap excludeIds(ContentIds other) {
    return ContentMap(
      inserts: _inserts.diffIdSet(other.inserts),
      deletes: _deletes.diffIdSet(other.deletes),
    );
  }

  /// Returns content present in this map and [other].
  ContentMap intersect(ContentMap other) {
    return ContentMap(
      inserts: _inserts.intersect(other._inserts),
      deletes: _deletes.intersect(other._deletes),
    );
  }

  /// Returns content present in this map and [other] ids.
  ContentMap intersectIds(ContentIds other) {
    return ContentMap(
      inserts: _inserts.intersectIdSet(other.inserts),
      deletes: _deletes.intersectIdSet(other.deletes),
    );
  }

  /// Returns ranges whose attributes satisfy the supplied predicates.
  ContentMap filter({
    required bool Function(List<ContentAttribute> attributes) insertPredicate,
    bool Function(List<ContentAttribute> attributes)? deletePredicate,
  }) {
    return ContentMap(
      inserts: _inserts.filter(insertPredicate),
      deletes: _deletes.filter(deletePredicate ?? insertPredicate),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ContentMap &&
        _inserts == other._inserts &&
        _deletes == other._deletes;
  }

  @override
  int get hashCode => Object.hash(_inserts, _deletes);
}

/// Returns the union of [contents].
ContentMap mergeContentMaps(Iterable<ContentMap> contents) {
  var result = ContentMap.empty();
  for (final content in contents) {
    result = result.merged(content);
  }
  return result;
}

IdMap _copyIdMap(IdMap source) {
  final copy = IdMap();
  source.insertInto(copy);
  return copy;
}

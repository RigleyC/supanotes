/// Insert/delete id-set metadata containers.
library;

import '../structs/id.dart';
import 'content_attribute.dart';
import 'content_map.dart';
import 'id_map.dart';
import 'id_range.dart';
import 'id_set.dart';

/// Selects the insert or delete branch of content metadata.
enum ContentBranch {
  /// Inserted content identifiers.
  inserts,

  /// Deleted content identifiers.
  deletes,
}

/// Immutable container for inserted and deleted content ids.
final class ContentIds {
  /// Creates content ids with defensive copies of [inserts] and [deletes].
  factory ContentIds({
    IdSet? inserts,
    IdSet? deletes,
  }) {
    return ContentIds._(
      inserts: _copyIdSet(inserts ?? IdSet()),
      deletes: _copyIdSet(deletes ?? IdSet()),
    );
  }

  const ContentIds._({
    required IdSet inserts,
    required IdSet deletes,
  })  : _inserts = inserts,
        _deletes = deletes;

  /// Creates empty content ids.
  factory ContentIds.empty() => ContentIds();

  /// Creates ids by dropping attributes from [contentMap].
  factory ContentIds.fromContentMap(ContentMap contentMap) {
    return ContentIds(
      inserts: contentMap.inserts.toIdSet(),
      deletes: contentMap.deletes.toIdSet(),
    );
  }

  final IdSet _inserts;
  final IdSet _deletes;

  /// Inserted content ids as a defensive copy.
  IdSet get inserts => _copyIdSet(_inserts);

  /// Deleted content ids as a defensive copy.
  IdSet get deletes => _copyIdSet(_deletes);

  /// Whether both branches are empty.
  bool get isEmpty => _inserts.isEmpty && _deletes.isEmpty;

  /// Whether at least one branch contains ids.
  bool get isNotEmpty => !isEmpty;

  /// Returns a content map with [insertAttributes] and [deleteAttributes].
  ContentMap toContentMap({
    Iterable<ContentAttribute> insertAttributes = const <ContentAttribute>[],
    Iterable<ContentAttribute>? deleteAttributes,
  }) {
    return ContentMap(
      inserts: IdMap.fromIdSet(_inserts, insertAttributes),
      deletes: IdMap.fromIdSet(
        _deletes,
        deleteAttributes ?? insertAttributes,
      ),
    );
  }

  /// Returns the union of this content and [other].
  ContentIds merged(ContentIds other) {
    return ContentIds(
      inserts: _inserts.merged(other._inserts),
      deletes: _deletes.merged(other._deletes),
    );
  }

  /// Returns this content with [other] removed.
  ContentIds exclude(ContentIds other) {
    return ContentIds(
      inserts: _inserts.diff(other._inserts),
      deletes: _deletes.diff(other._deletes),
    );
  }

  /// Returns content present in both this container and [other].
  ContentIds intersect(ContentIds other) {
    return ContentIds(
      inserts: _inserts.intersect(other._inserts),
      deletes: _deletes.intersect(other._deletes),
    );
  }

  /// Returns ranges accepted by [predicate].
  ContentIds filter(
    bool Function(ContentBranch branch, ClientId client, IdRange range)
        predicate,
  ) {
    return ContentIds(
      inserts: _filterIdSet(_inserts, ContentBranch.inserts, predicate),
      deletes: _filterIdSet(_deletes, ContentBranch.deletes, predicate),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ContentIds &&
        _inserts == other._inserts &&
        _deletes == other._deletes;
  }

  @override
  int get hashCode => Object.hash(_inserts, _deletes);
}

/// Returns the union of [contents].
ContentIds mergeContentIds(Iterable<ContentIds> contents) {
  var result = ContentIds.empty();
  for (final content in contents) {
    result = result.merged(content);
  }
  return result;
}

IdSet _copyIdSet(IdSet source) {
  final copy = IdSet();
  source.insertInto(copy);
  return copy;
}

IdSet _filterIdSet(
  IdSet source,
  ContentBranch branch,
  bool Function(ContentBranch branch, ClientId client, IdRange range) predicate,
) {
  final result = IdSet();
  source.forEach((client, range) {
    if (predicate(branch, client, range)) {
      result.addRange(client, range);
    }
  });
  return result;
}

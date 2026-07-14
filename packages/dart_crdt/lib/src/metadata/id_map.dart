/// Client-indexed maps from id ranges to content attributes.
library;

import 'dart:collection';

import '../structs/id.dart';
import 'attr_range.dart';
import 'attr_ranges.dart';
import 'content_attribute.dart';
import 'id_range.dart';
import 'id_ranges.dart';
import 'id_set.dart';

/// A normalized map of client-local ranges to content attributes.
final class IdMap {
  /// Creates an empty id map.
  IdMap() : _rangesByClient = _clientMap();

  /// Creates an id map from [idSet] with [attributes] attached to each range.
  factory IdMap.fromIdSet(
    IdSet idSet,
    Iterable<ContentAttribute> attributes,
  ) {
    final map = IdMap();
    idSet.forEach((client, range) {
      map.addRange(
        client,
        AttrRange(
          start: range.start,
          length: range.length,
          attributes: attributes,
        ),
      );
    });
    return map;
  }

  final SplayTreeMap<ClientId, AttrRanges> _rangesByClient;
  final Map<String, ContentAttribute> _attributesByKey =
      <String, ContentAttribute>{};

  /// The sorted clients present in this map.
  List<ClientId> get clients => List.unmodifiable(_rangesByClient.keys);

  /// The number of clients with at least one range.
  int get clientCount => _rangesByClient.length;

  /// Unique attributes currently referenced by ranges.
  List<ContentAttribute> get attributes {
    return List.unmodifiable(_attributesByKey.values);
  }

  /// Whether this map contains no ranges.
  bool get isEmpty => _rangesByClient.isEmpty;

  /// Whether this map contains at least one range.
  bool get isNotEmpty => _rangesByClient.isNotEmpty;

  /// Returns normalized ranges for [client].
  List<AttrRange> rangesFor(ClientId client) {
    return _rangesByClient[client]?.ranges ?? const <AttrRange>[];
  }

  /// Adds an attributed id range starting at [id].
  void add(
    Id id, {
    int length = 1,
    Iterable<ContentAttribute> attributes = const <ContentAttribute>[],
  }) {
    addRange(
      id.client,
      AttrRange(
        start: id.clock,
        length: length,
        attributes: attributes,
      ),
    );
  }

  /// Adds [range] for [client].
  void addRange(ClientId client, AttrRange range) {
    if (range.isEmpty) {
      return;
    }

    final canonical = AttrRange(
      start: range.start,
      length: range.length,
      attributes: _ensureAttributes(range.attributes),
    );
    final current = _rangesByClient[client] ?? AttrRanges.empty;
    _put(client, current.add(canonical));
  }

  /// Deletes an id range starting at [id].
  void delete(Id id, {int length = 1}) {
    deleteRange(id.client, IdRange(start: id.clock, length: length));
  }

  /// Deletes [range] for [client].
  void deleteRange(ClientId client, IdRange range) {
    if (range.isEmpty) {
      return;
    }

    final current = _rangesByClient[client];
    if (current == null) {
      return;
    }
    _put(client, current.delete(range));
    _pruneAttributes();
  }

  /// Returns whether [clock] is present for [client].
  bool has({
    required ClientId client,
    required Clock clock,
  }) {
    return _rangesByClient[client]?.has(clock) ?? false;
  }

  /// Returns whether [id] is present in this map.
  bool hasId(Id id) => has(client: id.client, clock: id.clock);

  /// Returns attributed and gap segments for [client] over [range].
  List<MaybeAttrRange> slice({
    required ClientId client,
    required IdRange range,
  }) {
    if (range.isEmpty) {
      return const <MaybeAttrRange>[];
    }
    return _rangesByClient[client]?.slice(range) ??
        <MaybeAttrRange>[
          MaybeAttrRange.gap(start: range.start, length: range.length),
        ];
  }

  /// Returns attributed and gap segments starting at [id].
  List<MaybeAttrRange> sliceId(Id id, {int length = 1}) {
    return slice(
      client: id.client,
      range: IdRange(start: id.clock, length: length),
    );
  }

  /// Returns the union of this map and [other].
  IdMap merged(IdMap other) {
    final result = IdMap();
    insertInto(result);
    other.insertInto(result);
    return result;
  }

  /// Returns ranges present in this map but not in [other].
  IdMap diff(IdMap other) {
    final result = IdMap();
    insertInto(result);
    other.forEach((client, range) => result.deleteRange(client, range.idRange));
    return result;
  }

  /// Returns ranges present in this map but not in [other].
  IdMap diffIdSet(IdSet other) {
    final result = IdMap();
    insertInto(result);
    other.forEach(result.deleteRange);
    return result;
  }

  /// Returns ranges present in both maps, joining attributes.
  IdMap intersect(IdMap other) {
    final result = IdMap();
    for (final entry in _rangesByClient.entries) {
      final otherRanges = other._rangesByClient[entry.key];
      if (otherRanges == null) {
        continue;
      }
      final overlap = entry.value.intersect(otherRanges);
      _insertRanges(result, entry.key, overlap);
    }
    return result;
  }

  /// Returns ranges present in this map and [other].
  IdMap intersectIdSet(IdSet other) {
    final result = IdMap();
    for (final client in clients) {
      final otherRanges = IdRanges(other.rangesFor(client));
      final overlap = _rangesByClient[client]!.intersectIdRanges(otherRanges);
      _insertRanges(result, client, overlap);
    }
    return result;
  }

  /// Returns ranges whose attributes satisfy [predicate].
  IdMap filter(bool Function(List<ContentAttribute> attributes) predicate) {
    final result = IdMap();
    forEach((client, range) {
      if (predicate(range.attributes)) {
        result.addRange(client, range);
      }
    });
    return result;
  }

  /// Inserts every range in this map into [target].
  void insertInto(IdMap target) {
    forEach(target.addRange);
  }

  /// Converts this map to an id set by dropping attributes.
  IdSet toIdSet() {
    final set = IdSet();
    forEach((client, range) => set.addRange(client, range.idRange));
    return set;
  }

  /// Invokes [visitor] for every client/range pair in sorted order.
  void forEach(void Function(ClientId client, AttrRange range) visitor) {
    for (final entry in _rangesByClient.entries) {
      entry.value.forEach((range) => visitor(entry.key, range));
    }
  }

  void _put(ClientId client, AttrRanges ranges) {
    if (ranges.isEmpty) {
      _rangesByClient.remove(client);
      return;
    }
    _rangesByClient[client] = ranges;
  }

  List<ContentAttribute> _ensureAttributes(
    Iterable<ContentAttribute> attributes,
  ) {
    return normalizeContentAttributes(attributes).map((attribute) {
      return _attributesByKey.putIfAbsent(attribute.stableKey, () => attribute);
    }).toList(growable: false);
  }

  void _pruneAttributes() {
    final retained = <String, ContentAttribute>{};
    forEach((_, range) {
      for (final attribute in range.attributes) {
        retained[attribute.stableKey] = attribute;
      }
    });
    _attributesByKey
      ..clear()
      ..addAll(retained);
  }

  @override
  bool operator ==(Object other) {
    if (other is! IdMap || clientCount != other.clientCount) {
      return false;
    }
    for (final entry in _rangesByClient.entries) {
      if (entry.value != other._rangesByClient[entry.key]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode {
    return Object.hashAll(
      _rangesByClient.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    );
  }
}

void _insertRanges(IdMap target, ClientId client, AttrRanges ranges) {
  for (final range in ranges.ranges) {
    target.addRange(client, range);
  }
}

SplayTreeMap<ClientId, T> _clientMap<T>() {
  return SplayTreeMap<ClientId, T>((left, right) => left.compareTo(right));
}

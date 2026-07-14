/// Client-indexed id range sets.
library;

import 'dart:collection';

import '../structs/id.dart';
import 'id_range.dart';
import 'id_ranges.dart';

/// A normalized set of client-local id ranges.
final class IdSet {
  /// Creates an empty id set.
  IdSet() : _rangesByClient = _clientMap();

  /// Creates a set populated from [rangesByClient].
  factory IdSet.fromRanges(Map<ClientId, Iterable<IdRange>> rangesByClient) {
    final set = IdSet();
    for (final entry in rangesByClient.entries) {
      for (final range in entry.value) {
        set.addRange(entry.key, range);
      }
    }
    return set;
  }

  final SplayTreeMap<ClientId, IdRanges> _rangesByClient;

  /// The sorted clients present in this set.
  List<ClientId> get clients => List.unmodifiable(_rangesByClient.keys);

  /// The number of clients with at least one range.
  int get clientCount => _rangesByClient.length;

  /// Whether this set contains no ranges.
  bool get isEmpty => _rangesByClient.isEmpty;

  /// Whether this set contains at least one range.
  bool get isNotEmpty => _rangesByClient.isNotEmpty;

  /// A defensive snapshot of the ranges indexed by client.
  Map<ClientId, List<IdRange>> get rangesByClient {
    final snapshot = _clientMap<List<IdRange>>();
    for (final entry in _rangesByClient.entries) {
      snapshot[entry.key] = entry.value.ranges;
    }
    return Map.unmodifiable(snapshot);
  }

  /// Returns the normalized ranges for [client].
  List<IdRange> rangesFor(ClientId client) {
    return _rangesByClient[client]?.ranges ?? const <IdRange>[];
  }

  /// Adds an id range starting at [id] and covering [length] clocks.
  void add(Id id, {int length = 1}) {
    addRange(id.client, IdRange(start: id.clock, length: length));
  }

  /// Adds [range] for [client].
  void addRange(ClientId client, IdRange range) {
    if (range.isEmpty) {
      return;
    }

    final current = _rangesByClient[client] ?? IdRanges.empty;
    _put(client, current.add(range));
  }

  /// Deletes an id range starting at [id] and covering [length] clocks.
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
  }

  /// Returns whether [clock] is present for [client].
  bool has({
    required ClientId client,
    required Clock clock,
  }) {
    return _rangesByClient[client]?.has(clock) ?? false;
  }

  /// Returns whether [id] is present in this set.
  bool hasId(Id id) => has(client: id.client, clock: id.clock);

  /// Returns the subset for [client] intersected with [range].
  IdSet slice({
    required ClientId client,
    required IdRange range,
  }) {
    final current = _rangesByClient[client];
    if (current == null) {
      return IdSet();
    }

    final sliced = current.slice(range);
    if (sliced.isEmpty) {
      return IdSet();
    }
    return IdSet.fromRanges({client: sliced.ranges});
  }

  /// Returns the union of this set and [other].
  IdSet merged(IdSet other) {
    final result = IdSet();
    insertInto(result);
    other.insertInto(result);
    return result;
  }

  /// Returns ids present in this set but not in [other].
  IdSet diff(IdSet other) {
    final result = IdSet();
    insertInto(result);
    other.forEach(result.deleteRange);
    return result;
  }

  /// Returns ids present in both this set and [other].
  IdSet intersect(IdSet other) {
    final result = IdSet();
    for (final entry in _rangesByClient.entries) {
      final otherRanges = other._rangesByClient[entry.key];
      if (otherRanges == null) {
        continue;
      }
      final overlap = entry.value.intersect(otherRanges);
      if (overlap.isNotEmpty) {
        result._rangesByClient[entry.key] = overlap;
      }
    }
    return result;
  }

  /// Inserts every range in this set into [target].
  void insertInto(IdSet target) {
    forEach(target.addRange);
  }

  /// Invokes [visitor] for every client/range pair in sorted order.
  void forEach(void Function(ClientId client, IdRange range) visitor) {
    for (final entry in _rangesByClient.entries) {
      entry.value.forEach((range) => visitor(entry.key, range));
    }
  }

  void _put(ClientId client, IdRanges ranges) {
    if (ranges.isEmpty) {
      _rangesByClient.remove(client);
      return;
    }
    _rangesByClient[client] = ranges;
  }

  @override
  bool operator ==(Object other) {
    if (other is! IdSet || clientCount != other.clientCount) {
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

  @override
  String toString() {
    return _rangesByClient.entries
        .map((entry) => '${entry.key.value}:[${entry.value}]')
        .join(';');
  }
}

SplayTreeMap<ClientId, T> _clientMap<T>() {
  return SplayTreeMap<ClientId, T>((left, right) => left.compareTo(right));
}

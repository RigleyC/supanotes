/// Range-based block sets used by update readers and writers.
library;

import 'dart:collection';
import 'dart:typed_data';

import '../binary/byte_reader.dart';
import '../binary/byte_writer.dart';
import '../binary/varint_codec.dart';
import '../metadata/id_range.dart';
import '../metadata/id_ranges.dart';
import '../metadata/id_set.dart';
import '../structs/id.dart';

/// A contiguous client-local block range.
final class BlockRange implements Comparable<BlockRange> {
  /// Creates a block range from [start] with [length] clocks.
  factory BlockRange({
    required Clock start,
    required int length,
  }) {
    final idRange = IdRange(start: start, length: length);
    return BlockRange._(idRange);
  }

  const BlockRange._(this.idRange);

  /// The covered id range.
  final IdRange idRange;

  /// The first clock in this block range.
  Clock get start => idRange.start;

  /// The number of clocks covered by this block range.
  int get length => idRange.length;

  /// The exclusive integer end bound.
  int get end => idRange.end;

  /// Whether this block range covers no clocks.
  bool get isEmpty => idRange.isEmpty;

  /// Returns a copy intersected with clocks at or above [clock].
  BlockRange? suffixFrom(Clock clock) {
    if (clock.value <= start.value) {
      return this;
    }
    if (clock.value >= end) {
      return null;
    }
    return BlockRange(start: clock, length: end - clock.value);
  }

  @override
  int compareTo(BlockRange other) => idRange.compareTo(other.idRange);

  @override
  bool operator ==(Object other) {
    return other is BlockRange && idRange == other.idRange;
  }

  @override
  int get hashCode => idRange.hashCode;

  @override
  String toString() => idRange.toString();
}

/// A deterministic set of block ranges grouped by client id.
final class BlockSet {
  /// Creates an empty block set.
  BlockSet() : _rangesByClient = _clientMap();

  /// Creates a block set populated from [rangesByClient].
  factory BlockSet.fromRanges(
    Map<ClientId, Iterable<BlockRange>> rangesByClient,
  ) {
    final set = BlockSet();
    for (final entry in rangesByClient.entries) {
      for (final range in entry.value) {
        set.addRange(entry.key, range);
      }
    }
    return set;
  }

  /// Reads a block set from [reader].
  factory BlockSet.read(ByteReader reader) => readBlockSet(reader);

  final SplayTreeMap<ClientId, IdRanges> _rangesByClient;

  /// Clients in deterministic descending update-write order.
  List<ClientId> get clients {
    return List.unmodifiable(_rangesByClient.keys.toList().reversed);
  }

  /// Number of clients with at least one block range.
  int get clientCount => _rangesByClient.length;

  /// Whether no block ranges are present.
  bool get isEmpty => _rangesByClient.isEmpty;

  /// Whether at least one block range is present.
  bool get isNotEmpty => _rangesByClient.isNotEmpty;

  /// Returns block ranges for [client] in ascending clock order.
  List<BlockRange> rangesFor(ClientId client) {
    final ranges = _rangesByClient[client]?.ranges ?? const <IdRange>[];
    return List.unmodifiable(ranges.map(BlockRange._));
  }

  /// Adds a block range starting at [id].
  void add(Id id, {int length = 1}) {
    addRange(id.client, BlockRange(start: id.clock, length: length));
  }

  /// Adds [range] for [client], merging overlap and touching ranges.
  void addRange(ClientId client, BlockRange range) {
    if (range.isEmpty) {
      return;
    }
    final current = _rangesByClient[client] ?? IdRanges.empty;
    _put(client, current.add(range.idRange));
  }

  /// Returns a new block set that contains this set and [other].
  BlockSet merged(BlockSet other) {
    final result = BlockSet();
    insertInto(result);
    other.insertInto(result);
    return result;
  }

  /// Returns a new block set excluding clocks below [knownState].
  BlockSet excludeKnown(Map<ClientId, Clock> knownState) {
    final result = BlockSet();
    forEach((client, range) {
      final knownClock = knownState[client];
      final retained =
          knownClock == null ? range : range.suffixFrom(knownClock);
      if (retained != null) {
        result.addRange(client, retained);
      }
    });
    return result;
  }

  /// Returns a state vector containing the exclusive end clock per client.
  Map<ClientId, Clock> stateVector() {
    final state = _clientMap<Clock>();
    for (final entry in _rangesByClient.entries) {
      final ranges = entry.value.ranges;
      if (ranges.isNotEmpty) {
        state[entry.key] = Clock(ranges.last.end);
      }
    }
    return Map.unmodifiable(state);
  }

  /// Converts this block set to id-only ranges.
  IdSet toIdSet() {
    final set = IdSet();
    forEach((client, range) => set.addRange(client, range.idRange));
    return set;
  }

  /// Inserts every block range in this set into [target].
  void insertInto(BlockSet target) {
    forEach(target.addRange);
  }

  /// Writes this block set to [writer].
  void write(ByteWriter writer) {
    writeBlockSet(writer, this);
  }

  /// Invokes [visitor] by descending client id, then ascending clock.
  void forEach(void Function(ClientId client, BlockRange range) visitor) {
    for (final client in clients) {
      final ranges = _rangesByClient[client]!;
      ranges.forEach((range) => visitor(client, BlockRange._(range)));
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
    if (other is! BlockSet || clientCount != other.clientCount) {
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

/// Writes [blocks] to [writer] in deterministic client order.
void writeBlockSet(ByteWriter writer, BlockSet blocks) {
  writeVarUint(writer, blocks.clientCount);
  for (final client in blocks.clients) {
    final ranges = blocks.rangesFor(client);
    writeClientId(writer, client);
    writeVarUint(writer, ranges.length);
    for (final range in ranges) {
      writeClock(writer, range.start);
      writeVarUint(writer, range.length);
    }
  }
}

/// Reads a block set from [reader].
BlockSet readBlockSet(ByteReader reader) {
  final clientCount = readVarUint(reader);
  final blocks = BlockSet();
  for (var clientIndex = 0; clientIndex < clientCount; clientIndex += 1) {
    final client = readClientId(reader);
    final rangeCount = readVarUint(reader);
    for (var rangeIndex = 0; rangeIndex < rangeCount; rangeIndex += 1) {
      final start = readClock(reader);
      final length = readVarUint(reader);
      blocks.addRange(client, BlockRange(start: start, length: length));
    }
  }
  return blocks;
}

/// Encodes [blocks] to an immutable byte buffer.
Uint8List encodeBlockSet(BlockSet blocks) {
  final writer = ByteWriter();
  writeBlockSet(writer, blocks);
  return writer.toBytes();
}

/// Decodes a block set from [bytes].
BlockSet decodeBlockSet(List<int> bytes) {
  return readBlockSet(ByteReader(bytes));
}

SplayTreeMap<ClientId, T> _clientMap<T>() {
  return SplayTreeMap<ClientId, T>((left, right) => left.compareTo(right));
}

part of 'struct_store.dart';

/// Stable view of a range inside a stored struct.
final class StructSlice {
  /// Creates a struct slice with validated [offset] and [length].
  StructSlice({
    required this.struct,
    required int offset,
    required int length,
  })  : offset = RangeError.checkValueInInterval(
          offset,
          0,
          struct.length,
          'offset',
        ),
        length = _checkSliceLength(struct, offset, length);

  /// The struct containing this slice.
  final AbstractStruct struct;

  /// Offset inside [struct].
  final int offset;

  /// Number of clocks covered by this slice.
  final int length;

  /// Id at the start of this slice.
  Id get id => struct.id.advance(offset);

  /// Id range covered by this slice.
  IdRange get range => IdRange(start: id.clock, length: length);

  /// Whether this slice covers the whole struct.
  bool get isFullStruct => offset == 0 && length == struct.length;
}

/// Iteration and clean-boundary helpers for [StructStore].
extension StructStoreIteration on StructStore {
  /// Returns overlapping slices without mutating stored structs.
  List<StructSlice> slicesWithoutSplitting({
    required ClientId client,
    required IdRange range,
  }) {
    if (range.isEmpty) {
      return const <StructSlice>[];
    }
    final structs = _structsByClient[client];
    if (structs == null || structs.isEmpty) {
      return const <StructSlice>[];
    }
    final result = <StructSlice>[];
    var index = _containingIndex(structs, range.start.value);
    if (index < 0) {
      index = _lowerBound(structs, range.start.value);
    }
    while (index < structs.length) {
      final struct = structs[index];
      if (struct.id.clock.value >= range.end) {
        break;
      }
      final start = _maxInt(struct.id.clock.value, range.start.value);
      final end = _minInt(struct.end, range.end);
      if (start < end) {
        result.add(
          StructSlice(
            struct: struct,
            offset: start - struct.id.clock.value,
            length: end - start,
          ),
        );
      }
      index += 1;
    }
    return List<StructSlice>.unmodifiable(result);
  }

  /// Returns structs in [range], splitting partial boundary structs first.
  List<AbstractStruct> structsWithSplitting({
    required ClientId client,
    required IdRange range,
  }) {
    if (range.isEmpty) {
      return const <AbstractStruct>[];
    }
    final structs = _structsByClient[client];
    if (structs == null || structs.isEmpty) {
      return const <AbstractStruct>[];
    }
    final start = range.start.value;
    final end = range.end;
    if (start >= getClock(client).value) {
      return const <AbstractStruct>[];
    }
    cleanStart(Id(client: client, clock: range.start));
    if (end < getClock(client).value &&
        structContaining(
              Id(client: client, clock: Clock(end)),
            ) !=
            null) {
      cleanStart(Id(client: client, clock: Clock(end)));
    }
    final result = <AbstractStruct>[];
    var index = _lowerBound(structs, start);
    while (index < structs.length && structs[index].id.clock.value < end) {
      result.add(structs[index]);
      index += 1;
    }
    return List<AbstractStruct>.unmodifiable(result);
  }

  /// Ensures a struct starts at [id] and returns it.
  AbstractStruct cleanStart(Id id) {
    final structs = _structsByClient[id.client];
    if (structs == null || structs.isEmpty) {
      throw StateError('No structs stored for client ${id.client.value}.');
    }
    final index = _containingIndex(structs, id.clock.value);
    if (index < 0) {
      throw StateError('No struct contains id $id.');
    }
    final struct = structs[index];
    if (struct.id.clock == id.clock) {
      return struct;
    }
    final right = struct.split(id.clock.value - struct.id.clock.value);
    structs.insert(index + 1, right);
    _trackSkip(right);
    return right;
  }

  /// Ensures the struct containing [id] ends at [id] and returns it.
  AbstractStruct cleanEnd(Id id) {
    final structs = _structsByClient[id.client];
    if (structs == null || structs.isEmpty) {
      throw StateError('No structs stored for client ${id.client.value}.');
    }
    final index = _containingIndex(structs, id.clock.value);
    if (index < 0) {
      throw StateError('No struct contains id $id.');
    }
    final struct = structs[index];
    if (id.clock.value == struct.end - 1) {
      return struct;
    }
    final right = struct.split(id.clock.value - struct.id.clock.value + 1);
    structs.insert(index + 1, right);
    _trackSkip(right);
    return struct;
  }
}

int _checkSliceLength(AbstractStruct struct, int offset, int length) {
  RangeError.checkNotNegative(length, 'length');
  if (offset + length > struct.length) {
    throw RangeError.range(length, 0, struct.length - offset, 'length');
  }
  return length;
}

int _maxInt(int left, int right) => left > right ? left : right;

int _minInt(int left, int right) => left < right ? left : right;

/// Client-local clock ranges used by metadata sets.
library;

import '../binary/varint_codec.dart';
import '../structs/id.dart';

/// A contiguous half-open range of client-local clocks.
final class IdRange implements Comparable<IdRange> {
  /// Creates a range from [start] with [length] clocks.
  factory IdRange({
    required Clock start,
    required int length,
  }) {
    _checkLength(start, length);
    return IdRange._(start, length);
  }

  const IdRange._(this.start, this.length);

  /// The first clock in the range.
  final Clock start;

  /// The number of clocks covered by this range.
  final int length;

  /// The exclusive integer end bound.
  int get end => start.value + length;

  /// Whether this range covers no clocks.
  bool get isEmpty => length == 0;

  /// Whether [clock] is inside this range.
  bool has(Clock clock) {
    return clock.value >= start.value && clock.value < end;
  }

  /// Whether this range overlaps [other].
  bool overlaps(IdRange other) {
    return !isEmpty &&
        !other.isEmpty &&
        start.value < other.end &&
        other.start.value < end;
  }

  /// Whether this range overlaps or directly touches [other].
  bool touches(IdRange other) {
    return !isEmpty &&
        !other.isEmpty &&
        start.value <= other.end &&
        other.start.value <= end;
  }

  /// Returns a merged range when [other] overlaps or touches this range.
  MaybeIdRange merge(IdRange other) {
    if (isEmpty) {
      return MaybeIdRange.of(other);
    }
    if (other.isEmpty) {
      return MaybeIdRange.of(this);
    }
    if (!touches(other)) {
      return const MaybeIdRange.empty();
    }

    final startValue =
        start.value < other.start.value ? start.value : other.start.value;
    final endValue = end > other.end ? end : other.end;
    return MaybeIdRange.of(
      IdRange(
        start: Clock(startValue),
        length: endValue - startValue,
      ),
    );
  }

  /// Returns the overlap between this range and [other].
  MaybeIdRange intersect(IdRange other) {
    final startValue =
        start.value > other.start.value ? start.value : other.start.value;
    final endValue = end < other.end ? end : other.end;
    if (startValue >= endValue) {
      return const MaybeIdRange.empty();
    }

    return MaybeIdRange.of(
      IdRange(
        start: Clock(startValue),
        length: endValue - startValue,
      ),
    );
  }

  /// Returns the parts of this range left after removing [other].
  List<IdRange> delete(IdRange other) {
    if (!overlaps(other)) {
      return isEmpty ? const <IdRange>[] : <IdRange>[this];
    }

    final pieces = <IdRange>[];
    if (other.start.value > start.value) {
      pieces.add(
        IdRange(
          start: start,
          length: other.start.value - start.value,
        ),
      );
    }

    if (other.end < end) {
      pieces.add(
        IdRange(
          start: Clock(other.end),
          length: end - other.end,
        ),
      );
    }
    return pieces;
  }

  @override
  int compareTo(IdRange other) {
    final startOrder = start.compareTo(other.start);
    if (startOrder != 0) {
      return startOrder;
    }
    return length.compareTo(other.length);
  }

  @override
  bool operator ==(Object other) {
    return other is IdRange && start == other.start && length == other.length;
  }

  @override
  int get hashCode => Object.hash(start, length);

  @override
  String toString() => '${start.value}+$length';
}

/// Optional wrapper for operations that may not produce a range.
final class MaybeIdRange {
  /// Creates an empty range result.
  const MaybeIdRange.empty() : _range = null;

  /// Creates a present range result unless [range] is empty.
  factory MaybeIdRange.of(IdRange range) {
    if (range.isEmpty) {
      return const MaybeIdRange.empty();
    }
    return MaybeIdRange._(range);
  }

  const MaybeIdRange._(this._range);

  final IdRange? _range;

  /// Whether this result contains no range.
  bool get isEmpty => _range == null;

  /// Whether this result contains a range.
  bool get isPresent => _range != null;

  /// Returns the contained range or throws when empty.
  IdRange get range {
    final value = _range;
    if (value == null) {
      throw StateError('No id range is present.');
    }
    return value;
  }

  /// Returns the contained range or `null` when empty.
  IdRange? get orNull => _range;

  @override
  bool operator ==(Object other) {
    return other is MaybeIdRange && _range == other._range;
  }

  @override
  int get hashCode => _range.hashCode;

  @override
  String toString() => _range?.toString() ?? 'empty';
}

void _checkLength(Clock start, int length) {
  RangeError.checkNotNegative(length, 'length');
  final maxLength = maxSafeInteger - start.value + 1;
  if (length > maxLength) {
    throw RangeError.range(length, 0, maxLength, 'length');
  }
}

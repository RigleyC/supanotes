/// Sorted range-list operations for a single client.
library;

import '../structs/id.dart';
import 'id_range.dart';

/// Normalized, sorted, non-overlapping ranges for one client.
final class IdRanges {
  /// Creates normalized ranges from [ranges].
  factory IdRanges(Iterable<IdRange> ranges) {
    return IdRanges._(_normalize(ranges));
  }

  const IdRanges._(this._ranges);

  /// An empty range list.
  static const empty = IdRanges._(<IdRange>[]);

  final List<IdRange> _ranges;

  /// The normalized ranges in ascending clock order.
  List<IdRange> get ranges => List.unmodifiable(_ranges);

  /// The number of stored ranges.
  int get length => _ranges.length;

  /// Whether there are no stored ranges.
  bool get isEmpty => _ranges.isEmpty;

  /// Whether there is at least one stored range.
  bool get isNotEmpty => _ranges.isNotEmpty;

  /// Returns whether [clock] exists in any stored range.
  bool has(Clock clock) {
    for (final range in _ranges) {
      if (range.has(clock)) {
        return true;
      }
      if (range.start.value > clock.value) {
        return false;
      }
    }
    return false;
  }

  /// Returns a new list with [range] inserted and merged.
  IdRanges add(IdRange range) {
    if (range.isEmpty) {
      return this;
    }
    return IdRanges(<IdRange>[..._ranges, range]);
  }

  /// Returns a new list with [range] removed.
  IdRanges delete(IdRange range) {
    if (range.isEmpty || isEmpty) {
      return this;
    }

    final next = <IdRange>[];
    for (final current in _ranges) {
      next.addAll(current.delete(range));
    }
    return IdRanges(next);
  }

  /// Returns the intersection between these ranges and [range].
  IdRanges slice(IdRange range) {
    if (range.isEmpty || isEmpty) {
      return empty;
    }

    final next = <IdRange>[];
    for (final current in _ranges) {
      final overlap = current.intersect(range).orNull;
      if (overlap != null) {
        next.add(overlap);
      }
      if (current.start.value >= range.end) {
        break;
      }
    }
    return IdRanges(next);
  }

  /// Returns the union of these ranges and [other].
  IdRanges merged(IdRanges other) {
    if (isEmpty) {
      return other;
    }
    if (other.isEmpty) {
      return this;
    }
    return IdRanges(<IdRange>[..._ranges, ...other._ranges]);
  }

  /// Returns ranges covered by this list but not by [other].
  IdRanges diff(IdRanges other) {
    var result = this;
    for (final range in other._ranges) {
      result = result.delete(range);
      if (result.isEmpty) {
        return empty;
      }
    }
    return result;
  }

  /// Returns ranges covered by both this list and [other].
  IdRanges intersect(IdRanges other) {
    if (isEmpty || other.isEmpty) {
      return empty;
    }

    final next = <IdRange>[];
    var leftIndex = 0;
    var rightIndex = 0;
    while (leftIndex < _ranges.length && rightIndex < other._ranges.length) {
      final left = _ranges[leftIndex];
      final right = other._ranges[rightIndex];
      final overlap = left.intersect(right).orNull;
      if (overlap != null) {
        next.add(overlap);
      }
      if (left.end < right.end) {
        leftIndex += 1;
      } else {
        rightIndex += 1;
      }
    }
    return IdRanges(next);
  }

  /// Invokes [visitor] for every stored range in ascending order.
  void forEach(void Function(IdRange range) visitor) {
    for (final range in _ranges) {
      visitor(range);
    }
  }

  @override
  bool operator ==(Object other) {
    if (other is! IdRanges || _ranges.length != other._ranges.length) {
      return false;
    }
    for (var index = 0; index < _ranges.length; index += 1) {
      if (_ranges[index] != other._ranges[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_ranges);

  @override
  String toString() => _ranges.join(',');
}

List<IdRange> _normalize(Iterable<IdRange> ranges) {
  final sorted = ranges.where((range) => !range.isEmpty).toList()..sort();
  if (sorted.isEmpty) {
    return const <IdRange>[];
  }

  final merged = <IdRange>[sorted.first];
  for (var index = 1; index < sorted.length; index += 1) {
    final next = sorted[index];
    final last = merged.last;
    final combined = last.merge(next).orNull;
    if (combined == null) {
      merged.add(next);
    } else {
      merged[merged.length - 1] = combined;
    }
  }
  return List.unmodifiable(merged);
}

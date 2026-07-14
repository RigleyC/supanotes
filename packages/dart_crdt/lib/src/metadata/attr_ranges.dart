/// Normalized lists of attribute ranges.
library;

import 'dart:collection';

import '../structs/id.dart';
import 'attr_range.dart';
import 'content_attribute.dart';
import 'id_range.dart';
import 'id_ranges.dart';

/// Sorted, non-overlapping attribution ranges for one client.
final class AttrRanges {
  /// Creates normalized ranges from [ranges].
  factory AttrRanges(Iterable<AttrRange> ranges) {
    return AttrRanges._(_normalize(ranges));
  }

  const AttrRanges._(this._ranges);

  /// An empty attribution range list.
  static const empty = AttrRanges._(<AttrRange>[]);

  final List<AttrRange> _ranges;

  /// The normalized ranges in ascending clock order.
  List<AttrRange> get ranges => List.unmodifiable(_ranges);

  /// Whether there are no stored ranges.
  bool get isEmpty => _ranges.isEmpty;

  /// Whether at least one range is stored.
  bool get isNotEmpty => _ranges.isNotEmpty;

  /// Returns whether [clock] is present in any range.
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

  /// Returns a new list with [range] inserted and normalized.
  AttrRanges add(AttrRange range) {
    if (range.isEmpty) {
      return this;
    }
    return AttrRanges(<AttrRange>[..._ranges, range]);
  }

  /// Returns a new list with [range] removed.
  AttrRanges delete(IdRange range) {
    if (range.isEmpty || isEmpty) {
      return this;
    }

    final next = <AttrRange>[];
    for (final current in _ranges) {
      for (final piece in current.idRange.delete(range)) {
        next.add(
          AttrRange(
            start: piece.start,
            length: piece.length,
            attributes: current.attributes,
          ),
        );
      }
    }
    return AttrRanges(next);
  }

  /// Returns attributed and gap segments for [range].
  List<MaybeAttrRange> slice(IdRange range) {
    if (range.isEmpty) {
      return const <MaybeAttrRange>[];
    }

    final result = <MaybeAttrRange>[];
    var cursor = range.start.value;
    for (final current in _ranges) {
      if (current.end <= cursor) {
        continue;
      }
      if (current.start.value >= range.end) {
        break;
      }
      if (cursor < current.start.value) {
        result.add(
          MaybeAttrRange.gap(
            start: Clock(cursor),
            length: current.start.value - cursor,
          ),
        );
      }

      final overlap = current.intersect(range).attributes;
      final overlapRange = current.idRange.intersect(range).orNull;
      if (overlap != null && overlapRange != null) {
        result.add(
          MaybeAttrRange.present(
            AttrRange(
              start: overlapRange.start,
              length: overlapRange.length,
              attributes: overlap,
            ),
          ),
        );
        cursor = overlapRange.end;
      }
    }

    if (cursor < range.end) {
      result.add(
        MaybeAttrRange.gap(
          start: Clock(cursor),
          length: range.end - cursor,
        ),
      );
    }
    return List.unmodifiable(result.where((item) => !item.isEmpty));
  }

  /// Returns the union of these ranges and [other].
  AttrRanges merged(AttrRanges other) {
    if (isEmpty) {
      return other;
    }
    if (other.isEmpty) {
      return this;
    }
    return AttrRanges(<AttrRange>[..._ranges, ...other._ranges]);
  }

  /// Returns ranges covered by this list but not by [other].
  AttrRanges diffIdRanges(IdRanges other) {
    var result = this;
    for (final range in other.ranges) {
      result = result.delete(range);
      if (result.isEmpty) {
        return empty;
      }
    }
    return result;
  }

  /// Returns ranges covered by this list but not by [other].
  AttrRanges diff(AttrRanges other) {
    var result = this;
    for (final range in other._ranges) {
      result = result.delete(range.idRange);
      if (result.isEmpty) {
        return empty;
      }
    }
    return result;
  }

  /// Returns ranges covered by both lists, joining attributes.
  AttrRanges intersect(AttrRanges other) {
    final next = <AttrRange>[];
    for (final left in _ranges) {
      for (final right in other._ranges) {
        final overlap = left.idRange.intersect(right.idRange).orNull;
        if (overlap != null) {
          next.add(
            AttrRange(
              start: overlap.start,
              length: overlap.length,
              attributes: <ContentAttribute>[
                ...left.attributes,
                ...right.attributes,
              ],
            ),
          );
        }
      }
    }
    return AttrRanges(next);
  }

  /// Returns ranges covered by this list and [other].
  AttrRanges intersectIdRanges(IdRanges other) {
    final next = <AttrRange>[];
    for (final left in _ranges) {
      for (final right in other.ranges) {
        final overlap = left.idRange.intersect(right).orNull;
        if (overlap != null) {
          next.add(
            AttrRange(
              start: overlap.start,
              length: overlap.length,
              attributes: left.attributes,
            ),
          );
        }
      }
    }
    return AttrRanges(next);
  }

  /// Returns ranges whose attributes satisfy [predicate].
  AttrRanges filter(
    bool Function(List<ContentAttribute> attributes) predicate,
  ) {
    return AttrRanges(_ranges.where((range) => predicate(range.attributes)));
  }

  /// Invokes [visitor] for every stored range.
  void forEach(void Function(AttrRange range) visitor) {
    for (final range in _ranges) {
      visitor(range);
    }
  }

  @override
  bool operator ==(Object other) {
    if (other is! AttrRanges || _ranges.length != other._ranges.length) {
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

List<AttrRange> _normalize(Iterable<AttrRange> ranges) {
  final source = ranges.where((range) => !range.isEmpty).toList();
  if (source.isEmpty) {
    return const <AttrRange>[];
  }

  final points = SplayTreeSet<int>();
  for (final range in source) {
    points
      ..add(range.start.value)
      ..add(range.end);
  }

  final sortedPoints = points.toList();
  final normalized = <AttrRange>[];
  for (var index = 0; index < sortedPoints.length - 1; index += 1) {
    final start = sortedPoints[index];
    final end = sortedPoints[index + 1];
    final active = source.where(
      (range) => range.start.value <= start && range.end >= end,
    );
    if (active.isEmpty) {
      continue;
    }

    final attributes = <ContentAttribute>[
      for (final range in active) ...range.attributes,
    ];
    _appendMerged(
      normalized,
      AttrRange(
        start: Clock(start),
        length: end - start,
        attributes: attributes,
      ),
    );
  }
  return List.unmodifiable(normalized);
}

void _appendMerged(List<AttrRange> ranges, AttrRange next) {
  if (ranges.isNotEmpty) {
    final last = ranges.last;
    if (last.end == next.start.value &&
        contentAttributesEqual(last.attributes, next.attributes)) {
      ranges[ranges.length - 1] = AttrRange(
        start: last.start,
        length: last.length + next.length,
        attributes: last.attributes,
      );
      return;
    }
  }
  ranges.add(next);
}

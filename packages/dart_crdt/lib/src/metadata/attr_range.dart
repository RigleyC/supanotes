/// Attribute-bearing clock ranges.
library;

import '../structs/id.dart';
import 'content_attribute.dart';
import 'id_range.dart';

/// A contiguous clock range with content attributes.
final class AttrRange implements Comparable<AttrRange> {
  /// Creates an attributed range.
  factory AttrRange({
    required Clock start,
    required int length,
    Iterable<ContentAttribute> attributes = const <ContentAttribute>[],
  }) {
    final idRange = IdRange(start: start, length: length);
    return AttrRange._(
      idRange,
      normalizeContentAttributes(attributes),
    );
  }

  const AttrRange._(this.idRange, this.attributes);

  /// The range covered by this attribution entry.
  final IdRange idRange;

  /// The attributes attached to this range.
  final List<ContentAttribute> attributes;

  /// The first clock in the range.
  Clock get start => idRange.start;

  /// The number of clocks covered by this range.
  int get length => idRange.length;

  /// The exclusive integer end bound.
  int get end => idRange.end;

  /// Whether this range covers no clocks.
  bool get isEmpty => idRange.isEmpty;

  /// Whether [clock] is inside this range.
  bool has(Clock clock) => idRange.has(clock);

  /// Returns a copy with replaced fields.
  AttrRange copyWith({
    Clock? start,
    int? length,
    Iterable<ContentAttribute>? attributes,
  }) {
    return AttrRange(
      start: start ?? this.start,
      length: length ?? this.length,
      attributes: attributes ?? this.attributes,
    );
  }

  /// Returns the overlap between this range and [range].
  MaybeAttrRange intersect(IdRange range) {
    final overlap = idRange.intersect(range).orNull;
    if (overlap == null) {
      return const MaybeAttrRange.empty();
    }
    return MaybeAttrRange.present(
      AttrRange(
        start: overlap.start,
        length: overlap.length,
        attributes: attributes,
      ),
    );
  }

  /// Returns a copy with [moreAttributes] joined into this range.
  AttrRange withAttributes(Iterable<ContentAttribute> moreAttributes) {
    return AttrRange(
      start: start,
      length: length,
      attributes: <ContentAttribute>[
        ...attributes,
        ...moreAttributes,
      ],
    );
  }

  @override
  int compareTo(AttrRange other) {
    final rangeOrder = idRange.compareTo(other.idRange);
    if (rangeOrder != 0) {
      return rangeOrder;
    }
    return attributes.length.compareTo(other.attributes.length);
  }

  @override
  bool operator ==(Object other) {
    return other is AttrRange &&
        idRange == other.idRange &&
        contentAttributesEqual(attributes, other.attributes);
  }

  @override
  int get hashCode => Object.hash(idRange, Object.hashAll(attributes));

  @override
  String toString() => '$idRange@$attributes';
}

/// Optional attribution range returned by slice operations.
final class MaybeAttrRange {
  /// Creates a missing slice segment.
  const MaybeAttrRange.empty()
      : _range = null,
        _gap = null;

  /// Creates a present attributed slice segment.
  factory MaybeAttrRange.present(AttrRange range) {
    if (range.isEmpty) {
      return const MaybeAttrRange.empty();
    }
    return MaybeAttrRange._(range);
  }

  /// Creates an unattributed gap segment.
  factory MaybeAttrRange.gap({
    required Clock start,
    required int length,
  }) {
    final range = IdRange(start: start, length: length);
    if (range.isEmpty) {
      return const MaybeAttrRange.empty();
    }
    return MaybeAttrRange._gap(range);
  }

  const MaybeAttrRange._(AttrRange range)
      : _range = range,
        _gap = null;

  const MaybeAttrRange._gap(IdRange range)
      : _range = null,
        _gap = range;

  final AttrRange? _range;
  final IdRange? _gap;

  /// Whether this segment represents no clocks.
  bool get isEmpty => _range == null && _gap == null;

  /// Whether this segment has an attributed range.
  bool get isPresent => _range != null;

  /// Whether this segment is a gap without attributes.
  bool get isGap => _gap != null;

  /// The range covered by this segment.
  IdRange get idRange {
    final present = _range;
    if (present != null) {
      return present.idRange;
    }
    final gap = _gap;
    if (gap != null) {
      return gap;
    }
    throw StateError('No attribution range is present.');
  }

  /// The attributes for this segment, or `null` when it is a gap.
  List<ContentAttribute>? get attributes => _range?.attributes;

  @override
  bool operator ==(Object other) {
    return other is MaybeAttrRange &&
        _range == other._range &&
        _gap == other._gap;
  }

  @override
  int get hashCode => Object.hash(_range, _gap);

  @override
  String toString() {
    if (_range != null) {
      return _range.toString();
    }
    if (_gap != null) {
      return 'gap:$_gap';
    }
    return 'empty';
  }
}

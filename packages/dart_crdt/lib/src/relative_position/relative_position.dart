/// Stable relative and absolute position value objects.
library;

import 'dart:typed_data';

import '../binary/byte_reader.dart';
import '../binary/byte_writer.dart';
import '../binary/string_buffer_codec.dart';
import '../binary/varint_codec.dart';
import '../content/content.dart';
import '../doc/doc.dart';
import '../structs/abstract_struct.dart';
import '../structs/id.dart';

part 'relative_position_codec.dart';
part 'relative_position_resolution.dart';

/// Thrown when a relative-position JSON or binary payload is invalid.
final class MalformedRelativePositionException implements FormatException {
  /// Creates an exception for malformed relative-position data.
  const MalformedRelativePositionException({
    required this.offset,
    required this.reason,
    this.source,
  });

  @override
  final int offset;

  /// The reason decoding failed.
  final String reason;

  @override
  final Object? source;

  @override
  String get message =>
      'Malformed relative position at offset $offset: $reason.';

  @override
  String toString() => 'MalformedRelativePositionException: $message';
}

/// A mutation-stable position anchored to an item, root type, or nested type.
final class RelativePosition implements Comparable<RelativePosition> {
  /// Creates a relative position.
  RelativePosition({
    this.typeId,
    this.rootName,
    this.itemId,
    int assoc = 0,
  }) : assoc = _checkAssoc(assoc) {
    _checkHasAnchor(typeId: typeId, rootName: rootName, itemId: itemId);
  }

  /// Creates a position anchored to [itemId].
  factory RelativePosition.item(Id itemId, {int assoc = 0}) {
    return RelativePosition(itemId: itemId, assoc: assoc);
  }

  /// Creates a position anchored to root shared type [rootName].
  factory RelativePosition.root(String rootName, {int assoc = 0}) {
    return RelativePosition(rootName: rootName, assoc: assoc);
  }

  /// Creates a position anchored to a nested shared type id.
  factory RelativePosition.type(Id typeId, {int assoc = 0}) {
    return RelativePosition(typeId: typeId, assoc: assoc);
  }

  /// Creates a position from [json].
  factory RelativePosition.fromJson(Map<String, Object?> json) {
    return RelativePosition(
      typeId: _optionalId(json['type'], 'type'),
      rootName: _optionalRootName(json),
      itemId: _optionalId(json['item'], 'item'),
      assoc: _optionalAssoc(json['assoc']),
    );
  }

  /// Nested shared type id used for end-of-type positions.
  final Id? typeId;

  /// Root shared type name used for end-of-root positions.
  final String? rootName;

  /// Item id used for positions associated with concrete content.
  final Id? itemId;

  /// Association direction. Negative values associate left, otherwise right.
  final int assoc;

  /// Converts this position to a JSON-compatible map.
  Map<String, Object?> toJson() => {
        if (typeId != null) 'type': typeId!.toJson(),
        if (rootName != null) 'tname': rootName,
        if (itemId != null) 'item': itemId!.toJson(),
        'assoc': assoc,
      };

  @override
  int compareTo(RelativePosition other) {
    return _firstNonZero([
      _compareNullableId(typeId, other.typeId),
      _compareNullableString(rootName, other.rootName),
      _compareNullableId(itemId, other.itemId),
      assoc.compareTo(other.assoc),
    ]);
  }

  @override
  bool operator ==(Object other) {
    return other is RelativePosition &&
        typeId == other.typeId &&
        rootName == other.rootName &&
        itemId == other.itemId &&
        assoc == other.assoc;
  }

  @override
  int get hashCode => Object.hash(typeId, rootName, itemId, assoc);

  @override
  String toString() {
    return 'RelativePosition(${toJson()})';
  }
}

/// A document-local position resolved from a [RelativePosition].
final class AbsolutePosition {
  /// Creates an absolute position in [type] at [index].
  AbsolutePosition({
    required this.type,
    required int index,
    int assoc = 0,
  })  : index = RangeError.checkNotNegative(index, 'index'),
        assoc = _checkAssoc(assoc);

  /// Shared type containing the resolved position.
  final SharedType type;

  /// Visible index inside [type].
  final int index;

  /// Association direction carried from the relative position.
  final int assoc;

  @override
  bool operator ==(Object other) {
    return other is AbsolutePosition &&
        identical(type, other.type) &&
        index == other.index &&
        assoc == other.assoc;
  }

  @override
  int get hashCode => Object.hash(identityHashCode(type), index, assoc);

  @override
  String toString() {
    return 'AbsolutePosition(type: ${type.name}, index: $index, assoc: $assoc)';
  }
}

/// Returns whether [left] and [right] describe the same relative position.
bool compareRelativePositions(RelativePosition? left, RelativePosition? right) {
  return left == right;
}

Id? _optionalId(Object? value, String key) {
  if (value == null) {
    return null;
  }
  if (value is! Map<String, Object?>) {
    throw MalformedRelativePositionException(
      offset: 0,
      reason: '$key must be an object',
      source: value,
    );
  }
  return Id(
    client: ClientId(_requiredInt(value, 'client')),
    clock: Clock(_requiredInt(value, 'clock')),
  );
}

String? _optionalRootName(Map<String, Object?> json) {
  final value = json.containsKey('tname') ? json['tname'] : json['rootName'];
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  throw MalformedRelativePositionException(
    offset: 0,
    reason: 'tname must be a string',
    source: value,
  );
}

int _optionalAssoc(Object? value) {
  if (value == null) {
    return 0;
  }
  if (value is int) {
    return _checkAssoc(value);
  }
  throw MalformedRelativePositionException(
    offset: 0,
    reason: 'assoc must be an integer',
    source: value,
  );
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  throw MalformedRelativePositionException(
    offset: 0,
    reason: '$key must be an integer',
    source: json,
  );
}

int _checkAssoc(int assoc) {
  return RangeError.checkValueInInterval(
    assoc,
    -maxSafeInteger,
    maxSafeInteger,
    'assoc',
  );
}

void _checkHasAnchor({
  required Id? typeId,
  required String? rootName,
  required Id? itemId,
}) {
  if (typeId == null && rootName == null && itemId == null) {
    throw ArgumentError('Relative position requires an anchor.');
  }
}

int _firstNonZero(Iterable<int> values) {
  for (final value in values) {
    if (value != 0) {
      return value;
    }
  }
  return 0;
}

int _compareNullableId(Id? left, Id? right) {
  if (left == null || right == null) {
    return _compareNull(left, right);
  }
  return left.compareTo(right);
}

int _compareNullableString(String? left, String? right) {
  if (left == null || right == null) {
    return _compareNull(left, right);
  }
  return left.compareTo(right);
}

int _compareNull(Object? left, Object? right) {
  if (left == null && right == null) {
    return 0;
  }
  return left == null ? -1 : 1;
}

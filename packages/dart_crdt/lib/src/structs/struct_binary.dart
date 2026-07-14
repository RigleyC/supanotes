/// Binary codecs for individual CRDT structs.
library;

import 'dart:typed_data';

import '../binary/byte_reader.dart';
import '../binary/byte_writer.dart';
import '../binary/string_buffer_codec.dart';
import '../binary/varint_codec.dart';
import '../content/content.dart';
import 'abstract_struct.dart';
import 'id.dart';

const _contentInfoMask = 0x1f;
const _hasParentSubBit = 0x20;
const _hasRightOriginBit = 0x40;
const _hasOriginBit = 0x80;

/// Thrown when an encoded struct is malformed.
final class MalformedStructException implements FormatException {
  /// Creates a malformed struct exception.
  const MalformedStructException({
    required this.offset,
    required this.reason,
  });

  @override
  final int offset;

  /// The reason decoding failed.
  final String reason;

  @override
  String get message => 'Malformed struct at offset $offset: $reason.';

  @override
  Object? get source => null;

  @override
  String toString() => 'MalformedStructException: $message';
}

/// Parent lookup used while reading item structs.
final class StructReadContext {
  /// Creates a read context.
  StructReadContext({
    Map<String, ItemParent>? parentsByKey,
    this.fallbackParent,
  }) : _parentsByKey = Map<String, ItemParent>.of(parentsByKey ?? const {});

  final Map<String, ItemParent> _parentsByKey;

  /// Parent to use when an item encodes only origin/right-origin references.
  final ItemParent? fallbackParent;

  /// Returns an existing or newly created root parent for [key].
  ItemParent parentForKey(String key) {
    return _parentsByKey.putIfAbsent(key, () => ItemParent(key: key));
  }

  /// Resolves a parent for items whose parent is implied by linked items.
  ItemParent parentForLinkedItem({required int offset}) {
    final parent = fallbackParent;
    if (parent == null) {
      throw MalformedStructException(
        offset: offset,
        reason: 'linked item requires a fallback parent',
      );
    }
    return parent;
  }
}

/// Writes [struct] using the current V1 struct payload layout.
void writeStructV1(
  ByteWriter writer,
  AbstractStruct struct, {
  int offset = 0,
  int offsetEnd = 0,
}) {
  struct.write(writer, offset: offset, offsetEnd: offsetEnd);
}

/// Writes [struct] using the V2 facade.
///
/// The compressed V2 update streams are implemented later; individual struct
/// payloads remain readable through this facade for fixture coverage.
void writeStructV2(
  ByteWriter writer,
  AbstractStruct struct, {
  int offset = 0,
  int offsetEnd = 0,
}) {
  writeStructV1(writer, struct, offset: offset, offsetEnd: offsetEnd);
}

/// Reads a V1 struct payload at [id].
AbstractStruct readStructV1(
  ByteReader reader, {
  required Id id,
  required StructReadContext context,
}) {
  final infoOffset = reader.offset;
  final info = reader.readByte();
  if (info == structGcRefNumber) {
    return GC(id: id, length: readVarUint(reader));
  }
  if (info == structSkipRefNumber) {
    return Skip(id: id, length: readVarUint(reader));
  }
  return _readItem(
    reader,
    id: id,
    info: info,
    infoOffset: infoOffset,
    context: context,
  );
}

/// Reads a V2 struct payload at [id].
AbstractStruct readStructV2(
  ByteReader reader, {
  required Id id,
  required StructReadContext context,
}) {
  return readStructV1(reader, id: id, context: context);
}

/// Encodes [struct] with V1 struct payload bytes.
Uint8List encodeStructV1(AbstractStruct struct) {
  final writer = ByteWriter();
  writeStructV1(writer, struct);
  return writer.toBytes();
}

/// Encodes [struct] with V2 struct payload bytes.
Uint8List encodeStructV2(AbstractStruct struct) {
  final writer = ByteWriter();
  writeStructV2(writer, struct);
  return writer.toBytes();
}

/// Decodes V1 struct payload [bytes] at [id].
AbstractStruct decodeStructV1(
  List<int> bytes, {
  required Id id,
  required StructReadContext context,
}) {
  final reader = ByteReader(bytes);
  final struct = readStructV1(reader, id: id, context: context);
  _requireDone(reader);
  return struct;
}

/// Decodes V2 struct payload [bytes] at [id].
AbstractStruct decodeStructV2(
  List<int> bytes, {
  required Id id,
  required StructReadContext context,
}) {
  final reader = ByteReader(bytes);
  final struct = readStructV2(reader, id: id, context: context);
  _requireDone(reader);
  return struct;
}

Item _readItem(
  ByteReader reader, {
  required Id id,
  required int info,
  required int infoOffset,
  required StructReadContext context,
}) {
  final origin = (info & _hasOriginBit) == 0 ? null : Id.read(reader);
  final rightOrigin = (info & _hasRightOriginBit) == 0 ? null : Id.read(reader);
  final hasParentSub = (info & _hasParentSubBit) != 0;
  final hasEncodedParent = origin == null && rightOrigin == null;
  final parent = hasEncodedParent
      ? context.parentForKey(readString(reader))
      : context.parentForLinkedItem(offset: infoOffset);
  final parentSub =
      hasEncodedParent && hasParentSub ? readString(reader) : null;
  final content = readContentByRef(reader, info & _contentInfoMask);
  return Item(
    id: id,
    origin: origin,
    rightOrigin: rightOrigin,
    parent: parent,
    parentSub: parentSub,
    content: content,
  );
}

void _requireDone(ByteReader reader) {
  if (reader.isDone) {
    return;
  }
  throw MalformedStructException(
    offset: reader.offset,
    reason: '${reader.remaining} trailing byte(s)',
  );
}

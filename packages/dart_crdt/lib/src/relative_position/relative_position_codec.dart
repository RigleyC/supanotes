part of 'relative_position.dart';

/// Writes [position] to [writer].
void writeRelativePosition(ByteWriter writer, RelativePosition position) {
  final itemId = position.itemId;
  if (itemId != null) {
    writeVarUint(writer, 0);
    itemId.write(writer);
  } else if (position.rootName != null) {
    writeVarUint(writer, 1);
    writeString(writer, position.rootName!);
  } else if (position.typeId != null) {
    writeVarUint(writer, 2);
    position.typeId!.write(writer);
  } else {
    throw StateError('Relative position has no anchor.');
  }
  writeVarInt(writer, position.assoc);
}

/// Reads a relative position from [reader].
RelativePosition readRelativePosition(ByteReader reader) {
  final kindOffset = reader.offset;
  final kind = readVarUint(reader);
  Id? typeId;
  String? rootName;
  Id? itemId;

  switch (kind) {
    case 0:
      itemId = Id.read(reader);
    case 1:
      rootName = readString(reader);
    case 2:
      typeId = Id.read(reader);
    default:
      throw MalformedRelativePositionException(
        offset: kindOffset,
        reason: 'unknown anchor kind $kind',
      );
  }

  final assoc = reader.isDone ? 0 : readVarInt(reader);
  return RelativePosition(
    typeId: typeId,
    rootName: rootName,
    itemId: itemId,
    assoc: assoc,
  );
}

/// Encodes [position] to immutable relative-position bytes.
Uint8List encodeRelativePosition(RelativePosition position) {
  final writer = ByteWriter();
  writeRelativePosition(writer, position);
  return writer.toBytes();
}

/// Decodes a complete relative-position byte payload.
RelativePosition decodeRelativePosition(List<int> bytes) {
  final reader = ByteReader(bytes);
  final position = readRelativePosition(reader);
  if (!reader.isDone) {
    throw MalformedRelativePositionException(
      offset: reader.offset,
      reason: '${reader.remaining} trailing byte(s)',
      source: bytes,
    );
  }
  return position;
}

part of 'state_update.dart';

void _writeClientPlan(Object encoder, _ClientPlan plan) {
  final entries = plan.entries;
  var clock = entries.first.start;
  var structCount = entries.length;
  for (final entry in entries) {
    if (entry.start > clock) {
      structCount += 1;
    }
    clock = entry.end;
  }

  writeVarUint(_restWriter(encoder), structCount);
  _writeClient(encoder, plan.client);
  writeVarUint(_restWriter(encoder), entries.first.start);

  clock = entries.first.start;
  for (final entry in entries) {
    if (entry.start > clock) {
      _writeStructPayload(
        encoder,
        Skip(
          id: Id(client: plan.client, clock: Clock(clock)),
          length: entry.start - clock,
        ),
        offset: 0,
        offsetEnd: 0,
      );
      clock = entry.start;
    }
    _writeStructPayload(
      encoder,
      entry.struct,
      offset: entry.offset,
      offsetEnd: entry.offsetEnd,
    );
    clock = entry.end;
  }
}

void _writeDeleteSet(Object encoder, IdSet deleteSet) {
  writeVarUint(_restWriter(encoder), deleteSet.clientCount);
  final clients = deleteSet.clients.toList()
    ..sort((left, right) => right.compareTo(left));
  for (final client in clients) {
    final ranges = deleteSet.rangesFor(client);
    _resetIdSet(encoder);
    writeClientId(_restWriter(encoder), client);
    writeVarUint(_restWriter(encoder), ranges.length);
    for (final range in ranges) {
      _writeIdSetClock(encoder, range.start);
      _writeIdSetLen(encoder, range.length);
    }
  }
}

void _writeStructPayload(
  Object encoder,
  AbstractStruct struct, {
  required int offset,
  required int offsetEnd,
}) {
  if (struct is GC) {
    _writeInfo(encoder, structGcRefNumber);
    _writeLen(encoder, struct.length - offset - offsetEnd);
    return;
  }
  if (struct is Skip) {
    _writeInfo(encoder, structSkipRefNumber);
    writeVarUint(_restWriter(encoder), struct.length - offset - offsetEnd);
    return;
  }
  if (struct is Item) {
    _writeItemPayload(
      encoder,
      struct,
      offset: offset,
      offsetEnd: offsetEnd,
    );
    return;
  }
  throw StateError('Unsupported struct type ${struct.runtimeType}.');
}

void _writeItemPayload(
  Object encoder,
  Item item, {
  required int offset,
  required int offsetEnd,
}) {
  final origin = offset == 0 ? item.origin : item.id.advance(offset - 1);
  final rightOrigin = item.rightOrigin;
  var header = item.content.ref & 0x1f;
  if (origin != null) {
    header |= 0x80;
  }
  if (rightOrigin != null) {
    header |= 0x40;
  }
  if (item.parentSub != null && item.origin == null && item.rightOrigin == null) {
    header |= 0x20;
  }

  _writeInfo(encoder, header);
  if (origin != null) {
    _writeLeftId(encoder, origin);
  }
  if (rightOrigin != null) {
    _writeRightId(encoder, rightOrigin);
  }
  if (origin == null && rightOrigin == null) {
    final parent = item.parent;
    if (parent == null) {
      throw StateError('Cannot write item without a parent reference.');
    }
    final definingId = parent.definingItemId;
    if (definingId == null) {
      _writeParentInfo(encoder, true);
      _writeString(encoder, parent.key);
    } else {
      // Nested type: reference the defining ContentType item id.
      _writeParentInfo(encoder, false);
      _writeLeftId(encoder, definingId);
    }
  }
  if (item.parentSub != null && item.origin == null && item.rightOrigin == null) {
    _writeString(encoder, item.parentSub!);
  }
  _writeContentPayload(
    encoder,
    item.content,
    offset: offset,
    offsetEnd: offsetEnd,
  );
}

void _writeYjsAny(Object encoder, Object? value) {
  final writer = (encoder as dynamic).restWriter;
  if (value == null) {
    writer.writeByte(126); // null
  } else if (value is String) {
    writer.writeByte(119); // string
    (encoder as dynamic).writeString(value);
  } else if (value is bool) {
    writer.writeByte(value ? 121 : 120); // true/false
  } else if (value is int) {
    writer.writeByte(125); // int
    writeVarInt(writer, value);
  } else if (value is double) {
    writer.writeByte(123); // float64
    final data = ByteData(8)..setFloat64(0, value, Endian.little);
    writer.writeBytes(data.buffer.asUint8List());
  } else if (value is Map) {
    writer.writeByte(118); // map
    writeVarUint(writer, value.length);
    for (final entry in value.entries) {
      (encoder as dynamic).writeString(entry.key.toString());
      _writeYjsAny(encoder, entry.value);
    }
  } else if (value is List) {
    writer.writeByte(117); // list
    writeVarUint(writer, value.length);
    for (final item in value) {
      _writeYjsAny(encoder, item);
    }
  } else if (value is AnyValue) {
    _writeYjsAny(encoder, value.toObject());
  } else {
    throw Exception('Unsupported Yjs Any type: ${value.runtimeType}');
  }
}

void _writeContentPayload(
  Object encoder,
  AbstractContent content, {
  required int offset,
  required int offsetEnd,
}) {
  switch (content) {
    case ContentAny(:final values):
      _writeLen(
        encoder,
        content.encodedLength(offset: offset, offsetEnd: offsetEnd),
      );
      for (final value
          in values.skip(offset).take(values.length - offset - offsetEnd)) {
        _writeYjsAny(encoder, value);
      }
    case ContentJson(:final values):
      _writeLen(
        encoder,
        content.encodedLength(offset: offset, offsetEnd: offsetEnd),
      );
      for (final value
          in values.skip(offset).take(values.length - offset - offsetEnd)) {
        _writeString(encoder, jsonEncode(value.toObject()));
      }
    case ContentBinary(:final bytes):
      content.encodedLength(offset: offset, offsetEnd: offsetEnd);
      _writeBuf(encoder, bytes);
    case ContentString(:final value):
      content.encodedLength(offset: offset, offsetEnd: offsetEnd);
      _writeString(encoder, value.substring(offset, value.length - offsetEnd));
    case ContentEmbed(:final value):
      content.encodedLength(offset: offset, offsetEnd: offsetEnd);
      _writeYjsAny(encoder, value);
    case ContentFormat(:final key, :final value):
      content.encodedLength(offset: offset, offsetEnd: offsetEnd);
      _writeKey(encoder, key);
      _writeYjsAny(encoder, value);
    case ContentType(:final sharedType):
      content.encodedLength(offset: offset, offsetEnd: offsetEnd);
      _writeTypeRef(encoder, sharedType.kind.ref);
      _writeString(encoder, sharedType.name);
    case ContentDocument(:final document):
      content.encodedLength(offset: offset, offsetEnd: offsetEnd);
      _writeString(encoder, document.guid);
      _writeAny(encoder, _documentOptions(document));
    case ContentDeleted():
      _writeLen(
        encoder,
        content.encodedLength(offset: offset, offsetEnd: offsetEnd),
      );
  }
}

AnyMap _documentOptions(Subdocument document) {
  final entries = <String, AnyValue>{};
  if (document.collectionId != null) {
    entries['collectionId'] = JsonString(document.collectionId!);
  }
  if (document.meta != const JsonNull()) {
    entries['meta'] = document.meta;
  }
  if (document.autoLoad) {
    entries['autoLoad'] = const JsonBool(true);
  }
  if (document.shouldLoad) {
    entries['shouldLoad'] = const JsonBool(true);
  }
  return AnyMap(entries);
}

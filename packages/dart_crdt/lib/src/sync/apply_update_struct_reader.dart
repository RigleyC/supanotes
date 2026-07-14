part of 'apply_update.dart';

AbstractStruct _readStruct(Object decoder, Doc document, Id id) {
  final infoOffset = _restReader(decoder).offset;
  final info = _readInfo(decoder);
  if (info == structGcRefNumber) {
    return GC(id: id, length: _readLen(decoder));
  }
  if (info == structSkipRefNumber) {
    return Skip(id: id, length: readVarUint(_restReader(decoder)));
  }
  return _readItem(decoder, document, id, info, infoOffset);
}

Item _readItem(
  Object decoder,
  Doc document,
  Id id,
  int info,
  int infoOffset,
) {
  final origin = (info & 0x80) == 0 ? null : _readLeftId(decoder);
  final rightOrigin = (info & 0x40) == 0 ? null : _readRightId(decoder);
  final hasParentSub = (info & 0x20) != 0;
  ItemParent? parent;
  String? parentSub;

  if (origin == null && rightOrigin == null) {
    if (_readParentInfo(decoder)) {
      parent = document.itemParentForKey(_readString(decoder));
    } else {
      // Nested type: the parent is the type defined by this item id.
      parent = document.itemParentForItemId(_readLeftId(decoder));
    }
  }
  if (hasParentSub) {
    parentSub = _readString(decoder);
  }

  return Item(
    id: id,
    origin: origin,
    rightOrigin: rightOrigin,
    parent: parent,
    parentSub: parentSub,
    content: _readContent(decoder, info & 0x1f),
  );
}

Object? _readYjsAny(Object decoder) {
  final reader = _restReader(decoder);
  final tag = reader.readByte();
  switch (tag) {
    case 127: // undefined
      return null;
    case 126: // null
      return null;
    case 119: // string
      return _readString(decoder);
    case 120: // false
      return false;
    case 121: // true
      return true;
    case 125: // integer
      return readVarInt(reader);
    case 124: // float32
      final bytes = reader.readBytes(4);
      return ByteData.sublistView(bytes).getFloat32(0, Endian.little);
    case 123: // float64
      final bytes = reader.readBytes(8);
      return ByteData.sublistView(bytes).getFloat64(0, Endian.little);
    case 122: // bigint
      final bytes = reader.readBytes(8);
      return ByteData.sublistView(bytes).getInt64(0, Endian.little);
    case 118: // map
      final len = readVarUint(reader);
      final map = <String, Object?>{};
      for (var i = 0; i < len; i++) {
        final key = _readString(decoder);
        map[key] = _readYjsAny(decoder);
      }
      return map;
    case 117: // list
      final len = readVarUint(reader);
      final list = <Object?>[];
      for (var i = 0; i < len; i++) {
        list.add(_readYjsAny(decoder));
      }
      return list;
    case 116: // binary
      final len = readVarUint(reader);
      return reader.readBytes(len);
    default:
      throw Exception('Unknown Yjs Any tag: $tag');
  }
}

List<AnyValue> _readYjsAnyArray(Object decoder) {
  final len = _readLen(decoder);
  final array = <AnyValue>[];
  for (var i = 0; i < len; i++) {
    array.add(AnyValue.fromObject(_readYjsAny(decoder)));
  }
  return array;
}

AbstractContent _readContent(Object decoder, int ref) {
  return switch (ref) {
    contentAnyRef => ContentAny(_readYjsAnyArray(decoder)),
    contentJsonRef => _readJsonContent(decoder),
    contentBinaryRef => ContentBinary(_readBuf(decoder)),
    contentStringRef => ContentString(_readString(decoder)),
    contentEmbedRef => ContentEmbed(_readYjsAny(decoder)),
    contentFormatRef => ContentFormat(
        key: _readKey(decoder),
        value: _readYjsAny(decoder),
      ),
    contentTypeRef => _readTypeContent(decoder),
    contentDocumentRef => _readDocumentContent(decoder),
    contentDeletedRef => ContentDeleted(_readLen(decoder)),
    _ => throw MalformedUpdateException(
        offset: _restReader(decoder).offset,
        reason: 'unknown content ref $ref',
      ),
  };
}

ContentAny _readAnyContent(Object decoder) {
  final length = _readLen(decoder);
  return ContentAny([
    for (var index = 0; index < length; index += 1) _readAny(decoder),
  ]);
}

ContentJson _readJsonContent(Object decoder) {
  final length = _readLen(decoder);
  return ContentJson([
    for (var index = 0; index < length; index += 1)
      JsonValue.fromObject(jsonDecode(_readString(decoder))),
  ]);
}

ContentType _readTypeContent(Object decoder) {
  final typeRefOffset = _restReader(decoder).offset;
  final typeRef = _readTypeRef(decoder);
  for (final kind in SharedTypeKind.values) {
    if (kind.ref == typeRef) {
      return ContentType(
        SharedTypePlaceholder(kind: kind, name: _readString(decoder)),
      );
    }
  }
  throw MalformedUpdateException(
    offset: typeRefOffset,
    reason: 'unknown shared type ref $typeRef',
  );
}

ContentDocument _readDocumentContent(Object decoder) {
  final guid = _readString(decoder);
  final options = _readAny(decoder);
  if (options is! AnyMap) {
    throw MalformedUpdateException(
      offset: _restReader(decoder).offset,
      reason: 'document options must be a map',
    );
  }
  return ContentDocument(
    guid: guid,
    collectionId: _optionalString(options.entries, 'collectionId'),
    meta: options.entries['meta'],
    autoLoad: _optionalBool(options.entries, 'autoLoad'),
    shouldLoad: _optionalBool(options.entries, 'shouldLoad'),
  );
}

String? _optionalString(Map<String, AnyValue> options, String key) {
  final value = options[key];
  if (value == null) {
    return null;
  }
  if (value is JsonString) {
    return value.value;
  }
  throw MalformedUpdateException(offset: 0, reason: '$key must be a string');
}

bool _optionalBool(Map<String, AnyValue> options, String key) {
  final value = options[key];
  if (value == null) {
    return false;
  }
  if (value is JsonBool) {
    return value.value;
  }
  throw MalformedUpdateException(offset: 0, reason: '$key must be a boolean');
}

IdSet _readDeleteSet(Object decoder) {
  final deleteSet = IdSet();
  final clientCount = readVarUint(_restReader(decoder));
  for (var clientIndex = 0; clientIndex < clientCount; clientIndex += 1) {
    _resetIdSet(decoder);
    final client = readClientId(_restReader(decoder));
    final rangeCount = readVarUint(_restReader(decoder));
    for (var index = 0; index < rangeCount; index += 1) {
      final start = _readIdSetClock(decoder);
      final length = _readIdSetLen(decoder);
      deleteSet.addRange(client, IdRange(start: start, length: length));
    }
  }
  return deleteSet;
}

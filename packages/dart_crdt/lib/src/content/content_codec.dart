part of 'content.dart';

/// Thrown when an encoded content payload is malformed.
final class MalformedContentException implements FormatException {
  /// Creates a malformed content exception.
  const MalformedContentException({
    required this.offset,
    required this.reason,
  });

  @override
  final int offset;

  /// The reason decoding failed.
  final String reason;

  @override
  String get message => 'Malformed content at offset $offset: $reason.';

  @override
  Object? get source => null;

  @override
  String toString() => 'MalformedContentException: $message';
}

/// Reads content payload identified by [ref].
AbstractContent readContentByRef(ByteReader reader, int ref) {
  return switch (ref) {
    contentDeletedRef => ContentDeleted(readVarUint(reader)),
    contentJsonRef => _readJsonContent(reader),
    contentBinaryRef => ContentBinary(readByteBuffer(reader)),
    contentStringRef => ContentString(readString(reader)),
    contentEmbedRef => ContentEmbed(readJsonValue(reader).toObject()),
    contentFormatRef => _readFormatContent(reader),
    contentTypeRef => _readTypeContent(reader),
    contentAnyRef => _readAnyContent(reader),
    contentDocumentRef => _readDocumentContent(reader),
    _ => throw MalformedContentException(
        offset: reader.offset,
        reason: 'unknown content ref $ref',
      ),
  };
}

ContentAny _readAnyContent(ByteReader reader) {
  final count = readVarUint(reader);
  return ContentAny([
    for (var index = 0; index < count; index += 1) readAnyValue(reader),
  ]);
}

ContentJson _readJsonContent(ByteReader reader) {
  final count = readVarUint(reader);
  return ContentJson([
    for (var index = 0; index < count; index += 1)
      JsonValue.fromObject(jsonDecode(readString(reader))),
  ]);
}

ContentFormat _readFormatContent(ByteReader reader) {
  return ContentFormat(
    key: readString(reader),
    value: readAnyValue(reader).toObject(),
  );
}

ContentType _readTypeContent(ByteReader reader) {
  final refOffset = reader.offset;
  final typeRef = readVarUint(reader);
  final kind = _sharedTypeKindFromRef(typeRef, refOffset);
  return ContentType(
    SharedTypePlaceholder(kind: kind, name: readString(reader)),
  );
}

ContentDocument _readDocumentContent(ByteReader reader) {
  final guid = readString(reader);
  final optionsOffset = reader.offset;
  final optionsValue = readAnyValue(reader);
  if (optionsValue is! AnyMap) {
    throw MalformedContentException(
      offset: optionsOffset,
      reason: 'document options must be a map',
    );
  }
  final options = optionsValue.entries;
  return ContentDocument(
    guid: guid,
    collectionId: _optionalString(options, 'collectionId'),
    meta: options['meta'],
    autoLoad: _optionalBool(options, 'autoLoad'),
    shouldLoad: _optionalBool(options, 'shouldLoad'),
  );
}

SharedTypeKind _sharedTypeKindFromRef(int ref, int offset) {
  for (final kind in SharedTypeKind.values) {
    if (kind.ref == ref) {
      return kind;
    }
  }
  throw MalformedContentException(
    offset: offset,
    reason: 'unknown shared type ref $ref',
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
  throw MalformedContentException(
    offset: 0,
    reason: '$key must be a string',
  );
}

bool _optionalBool(Map<String, AnyValue> options, String key) {
  final value = options[key];
  if (value == null) {
    return false;
  }
  if (value is JsonBool) {
    return value.value;
  }
  throw MalformedContentException(
    offset: 0,
    reason: '$key must be a boolean',
  );
}

/// Binary codecs for attributed id maps.
library;

import '../binary/any_codec.dart';
import '../binary/byte_reader.dart';
import '../binary/byte_writer.dart';
import '../binary/string_buffer_codec.dart';
import '../binary/varint_codec.dart';
import '../structs/id.dart';
import 'attr_range.dart';
import 'content_attribute.dart';
import 'id_map.dart';

/// Thrown when encoded id-map bytes are malformed.
final class MalformedIdMapException implements FormatException {
  /// Creates an exception for malformed input at [offset].
  const MalformedIdMapException({
    required this.offset,
    required this.reason,
  });

  @override
  final int offset;

  /// The reason decoding failed.
  final String reason;

  @override
  String get message => 'Malformed id map at offset $offset: $reason.';

  @override
  Object? get source => null;
}

/// V1 binary writer for [IdMap].
abstract final class IdMapEncoderV1 {
  /// Writes [map] to [writer].
  static void write(ByteWriter writer, IdMap map) => _writeIdMap(writer, map);
}

/// V1 binary reader for [IdMap].
abstract final class IdMapDecoderV1 {
  /// Reads an id map from [reader].
  static IdMap read(ByteReader reader) => _readIdMap(reader);
}

/// V2 binary writer for [IdMap].
abstract final class IdMapEncoderV2 {
  /// Writes [map] to [writer].
  static void write(ByteWriter writer, IdMap map) => _writeIdMap(writer, map);
}

/// V2 binary reader for [IdMap].
abstract final class IdMapDecoderV2 {
  /// Reads an id map from [reader].
  static IdMap read(ByteReader reader) => _readIdMap(reader);
}

void _writeIdMap(ByteWriter writer, IdMap map) {
  final attrIdsByKey = <String, int>{};
  final nameIdsByName = <String, int>{};

  writeVarUint(writer, map.clientCount);
  for (final client in map.clients) {
    final ranges = map.rangesFor(client);
    writeClientId(writer, client);
    writeVarUint(writer, ranges.length);
    for (final range in ranges) {
      writeClock(writer, range.start);
      writeVarUint(writer, range.length);
      writeVarUint(writer, range.attributes.length);
      for (final attribute in range.attributes) {
        _writeAttribute(writer, attribute, attrIdsByKey, nameIdsByName);
      }
    }
  }
}

IdMap _readIdMap(ByteReader reader) {
  final clientCount = readVarUint(reader);
  final attributes = <ContentAttribute>[];
  final names = <String>[];
  final map = IdMap();

  for (var clientIndex = 0; clientIndex < clientCount; clientIndex += 1) {
    final client = readClientId(reader);
    final rangeCount = readVarUint(reader);
    for (var rangeIndex = 0; rangeIndex < rangeCount; rangeIndex += 1) {
      final start = readClock(reader);
      final length = readVarUint(reader);
      final attrCount = readVarUint(reader);
      final rangeAttributes = <ContentAttribute>[
        for (var index = 0; index < attrCount; index += 1)
          _readAttribute(reader, attributes, names),
      ];
      map.addRange(
        client,
        AttrRange(
          start: start,
          length: length,
          attributes: rangeAttributes,
        ),
      );
    }
  }
  return map;
}

void _writeAttribute(
  ByteWriter writer,
  ContentAttribute attribute,
  Map<String, int> attrIdsByKey,
  Map<String, int> nameIdsByName,
) {
  final existingAttrId = attrIdsByKey[attribute.stableKey];
  if (existingAttrId != null) {
    writeVarUint(writer, existingAttrId);
    return;
  }

  final attrId = attrIdsByKey.length;
  attrIdsByKey[attribute.stableKey] = attrId;
  writeVarUint(writer, attrId);

  final existingNameId = nameIdsByName[attribute.name];
  if (existingNameId != null) {
    writeVarUint(writer, existingNameId);
  } else {
    final nameId = nameIdsByName.length;
    nameIdsByName[attribute.name] = nameId;
    writeVarUint(writer, nameId);
    writeString(writer, attribute.name);
  }
  writeAnyValue(writer, attribute.value);
}

ContentAttribute _readAttribute(
  ByteReader reader,
  List<ContentAttribute> attributes,
  List<String> names,
) {
  final attrOffset = reader.offset;
  final attrId = readVarUint(reader);
  if (attrId < attributes.length) {
    return attributes[attrId];
  }
  if (attrId > attributes.length) {
    throw MalformedIdMapException(
      offset: attrOffset,
      reason: 'attribute id $attrId skips ${attributes.length}',
    );
  }

  final name = _readAttributeName(reader, names);
  final attribute = ContentAttribute.fromAny(
    name: name,
    value: readAnyValue(reader),
  );
  attributes.add(attribute);
  return attribute;
}

String _readAttributeName(ByteReader reader, List<String> names) {
  final nameOffset = reader.offset;
  final nameId = readVarUint(reader);
  if (nameId < names.length) {
    return names[nameId];
  }
  if (nameId > names.length) {
    throw MalformedIdMapException(
      offset: nameOffset,
      reason: 'attribute name id $nameId skips ${names.length}',
    );
  }

  final name = readString(reader);
  names.add(name);
  return name;
}

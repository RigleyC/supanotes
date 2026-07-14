/// Binary codecs for content metadata containers.
library;

import 'dart:typed_data';

import '../binary/byte_reader.dart';
import '../binary/byte_writer.dart';
import 'content_ids.dart';
import 'content_map.dart';
import 'id_map_codec.dart';
import 'id_set_codec.dart';

/// Writes [contentIds] with the default V2 content-id encoding.
void writeContentIds(ByteWriter writer, ContentIds contentIds) {
  writeContentIdsV2(writer, contentIds);
}

/// Reads content ids with the default V2 content-id encoding.
ContentIds readContentIds(ByteReader reader) => readContentIdsV2(reader);

/// Encodes [contentIds] with the default V2 content-id encoding.
Uint8List encodeContentIds(ContentIds contentIds) {
  return encodeContentIdsV2(contentIds);
}

/// Decodes content ids with the default V2 content-id encoding.
ContentIds decodeContentIds(List<int> bytes) => decodeContentIdsV2(bytes);

/// Writes [contentIds] as insert id set followed by delete id set.
void writeContentIdsV1(ByteWriter writer, ContentIds contentIds) {
  IdSetEncoderV1.write(writer, contentIds.inserts);
  IdSetEncoderV1.write(writer, contentIds.deletes);
}

/// Reads insert and delete id sets from [reader].
ContentIds readContentIdsV1(ByteReader reader) {
  return ContentIds(
    inserts: IdSetDecoderV1.read(reader),
    deletes: IdSetDecoderV1.read(reader),
  );
}

/// Encodes [contentIds] using V1 id-set wrappers.
Uint8List encodeContentIdsV1(ContentIds contentIds) {
  final writer = ByteWriter();
  writeContentIdsV1(writer, contentIds);
  return writer.toBytes();
}

/// Decodes [bytes] using V1 id-set wrappers.
ContentIds decodeContentIdsV1(List<int> bytes) {
  return readContentIdsV1(ByteReader(bytes));
}

/// Writes [contentIds] as insert id set followed by delete id set.
void writeContentIdsV2(ByteWriter writer, ContentIds contentIds) {
  IdSetEncoderV2.write(writer, contentIds.inserts);
  IdSetEncoderV2.write(writer, contentIds.deletes);
}

/// Reads insert and delete id sets from [reader].
ContentIds readContentIdsV2(ByteReader reader) {
  return ContentIds(
    inserts: IdSetDecoderV2.read(reader),
    deletes: IdSetDecoderV2.read(reader),
  );
}

/// Encodes [contentIds] using V2 id-set wrappers.
Uint8List encodeContentIdsV2(ContentIds contentIds) {
  final writer = ByteWriter();
  writeContentIdsV2(writer, contentIds);
  return writer.toBytes();
}

/// Decodes [bytes] using V2 id-set wrappers.
ContentIds decodeContentIdsV2(List<int> bytes) {
  return readContentIdsV2(ByteReader(bytes));
}

/// Writes [contentMap] with the default V2 content-map encoding.
void writeContentMap(ByteWriter writer, ContentMap contentMap) {
  writeContentMapV2(writer, contentMap);
}

/// Reads a content map with the default V2 content-map encoding.
ContentMap readContentMap(ByteReader reader) => readContentMapV2(reader);

/// Encodes [contentMap] with the default V2 content-map encoding.
Uint8List encodeContentMap(ContentMap contentMap) {
  return encodeContentMapV2(contentMap);
}

/// Decodes a content map with the default V2 content-map encoding.
ContentMap decodeContentMap(List<int> bytes) => decodeContentMapV2(bytes);

/// Writes [contentMap] as insert id map followed by delete id map.
void writeContentMapV1(ByteWriter writer, ContentMap contentMap) {
  IdMapEncoderV1.write(writer, contentMap.inserts);
  IdMapEncoderV1.write(writer, contentMap.deletes);
}

/// Reads insert and delete id maps from [reader].
ContentMap readContentMapV1(ByteReader reader) {
  return ContentMap(
    inserts: IdMapDecoderV1.read(reader),
    deletes: IdMapDecoderV1.read(reader),
  );
}

/// Encodes [contentMap] using V1 id-map wrappers.
Uint8List encodeContentMapV1(ContentMap contentMap) {
  final writer = ByteWriter();
  writeContentMapV1(writer, contentMap);
  return writer.toBytes();
}

/// Decodes [bytes] using V1 id-map wrappers.
ContentMap decodeContentMapV1(List<int> bytes) {
  return readContentMapV1(ByteReader(bytes));
}

/// Writes [contentMap] as insert id map followed by delete id map.
void writeContentMapV2(ByteWriter writer, ContentMap contentMap) {
  IdMapEncoderV2.write(writer, contentMap.inserts);
  IdMapEncoderV2.write(writer, contentMap.deletes);
}

/// Reads insert and delete id maps from [reader].
ContentMap readContentMapV2(ByteReader reader) {
  return ContentMap(
    inserts: IdMapDecoderV2.read(reader),
    deletes: IdMapDecoderV2.read(reader),
  );
}

/// Encodes [contentMap] using V2 id-map wrappers.
Uint8List encodeContentMapV2(ContentMap contentMap) {
  final writer = ByteWriter();
  writeContentMapV2(writer, contentMap);
  return writer.toBytes();
}

/// Decodes [bytes] using V2 id-map wrappers.
ContentMap decodeContentMapV2(List<int> bytes) {
  return readContentMapV2(ByteReader(bytes));
}

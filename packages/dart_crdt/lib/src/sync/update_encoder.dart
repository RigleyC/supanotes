/// V1 and V2 update encoders.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../binary/any_codec.dart';
import '../binary/any_value.dart';
import '../binary/byte_writer.dart';
import '../binary/rle_codec.dart';
import '../binary/string_buffer_codec.dart' as string_codec;
import '../binary/uint_opt_rle_codec.dart';
import '../binary/varint_codec.dart';
import '../metadata/id_set_codec.dart';
import '../structs/id.dart';

/// V1 update encoder with direct varint fields.
final class UpdateEncoderV1 extends IdSetEncoderV1 {
  /// Creates an empty V1 update encoder.
  UpdateEncoderV1();

  /// Writes a left-origin [id].
  void writeLeftId(Id id) {
    id.write(restWriter);
  }

  /// Writes a right-origin [id].
  void writeRightId(Id id) {
    id.write(restWriter);
  }

  /// Writes a [client] id.
  void writeClient(ClientId client) {
    writeClientId(restWriter, client);
  }

  /// Writes an unsigned byte [info].
  void writeInfo(int info) {
    restWriter.writeByte(info);
  }

  /// Writes a length-prefixed UTF-8 [value].
  void writeString(String value) {
    string_codec.writeString(restWriter, value);
  }

  /// Writes whether a parent reference is keyed by root name.
  void writeParentInfo(bool isKey) {
    writeVarUint(restWriter, isKey ? 1 : 0);
  }

  /// Writes a shared type reference id.
  void writeTypeRef(int typeRef) {
    writeVarUint(restWriter, typeRef);
  }

  /// Writes a struct [length].
  void writeLen(int length) {
    writeVarUint(restWriter, length);
  }

  /// Writes an arbitrary binary-capable [value].
  void writeAny(AnyValue value) {
    writeAnyValue(restWriter, value);
  }

  /// Writes a length-prefixed byte [buffer].
  void writeBuf(List<int> buffer) {
    string_codec.writeByteBuffer(restWriter, buffer);
  }

  /// Writes a legacy JSON [value] as a JSON string.
  void writeJson(JsonValue value) {
    writeString(jsonEncode(value.toObject()));
  }

  /// Writes a string [key] directly.
  void writeKey(String key) {
    writeString(key);
  }
}

/// V2 update encoder with composed RLE streams and an unprefixed rest buffer.
final class UpdateEncoderV2 extends IdSetEncoderV2 {
  /// Creates an empty V2 update encoder.
  UpdateEncoderV2();

  final Map<String, int> _keyClocks = <String, int>{};
  final IntDiffOptRleEncoder _keyClockEncoder = IntDiffOptRleEncoder();
  final UintOptRleEncoder _clientEncoder = UintOptRleEncoder();
  final IntDiffOptRleEncoder _leftClockEncoder = IntDiffOptRleEncoder();
  final IntDiffOptRleEncoder _rightClockEncoder = IntDiffOptRleEncoder();
  final UintRleEncoder _infoEncoder = UintRleEncoder();
  final ByteWriter _stringWriter = ByteWriter();
  final UintRleEncoder _parentInfoEncoder = UintRleEncoder();
  final UintOptRleEncoder _typeRefEncoder = UintOptRleEncoder();
  final UintOptRleEncoder _lenEncoder = UintOptRleEncoder();
  Uint8List? _closedBytes;

  /// Writes a left-origin [id].
  void writeLeftId(Id id) {
    _clientEncoder.write(id.client.value);
    _leftClockEncoder.write(id.clock.value);
  }

  /// Writes a right-origin [id].
  void writeRightId(Id id) {
    _clientEncoder.write(id.client.value);
    _rightClockEncoder.write(id.clock.value);
  }

  /// Writes a [client] id.
  void writeClient(ClientId client) {
    _clientEncoder.write(client.value);
  }

  /// Writes an unsigned byte [info].
  void writeInfo(int info) {
    RangeError.checkValueInInterval(info, 0, 255, 'info');
    _infoEncoder.write(info);
  }

  /// Writes [value] to the shared string stream.
  void writeString(String value) {
    string_codec.writeString(_stringWriter, value);
  }

  /// Writes whether a parent reference is keyed by root name.
  void writeParentInfo(bool isKey) {
    _parentInfoEncoder.write(isKey ? 1 : 0);
  }

  /// Writes a shared type reference id.
  void writeTypeRef(int typeRef) {
    _typeRefEncoder.write(typeRef);
  }

  /// Writes a struct [length].
  void writeLen(int length) {
    _lenEncoder.write(length);
  }

  /// Writes an arbitrary binary-capable [value] to the rest buffer.
  void writeAny(AnyValue value) {
    writeAnyValue(restWriter, value);
  }

  /// Writes a length-prefixed byte [buffer] to the rest buffer.
  void writeBuf(List<int> buffer) {
    string_codec.writeByteBuffer(restWriter, buffer);
  }

  /// Writes a legacy JSON [value] using the binary any-value codec.
  void writeJson(AnyValue value) {
    writeAny(value);
  }

  /// Writes a cached string [key] reference.
  void writeKey(String key) {
    final clock = _keyClocks[key];
    if (clock != null) {
      _keyClockEncoder.write(clock);
      return;
    }

    final nextClock = _keyClocks.length;
    _keyClocks[key] = nextClock;
    _keyClockEncoder.write(nextClock);
    writeString(key);
  }

  @override
  Uint8List toBytes() {
    if (_closedBytes != null) {
      return _closedBytes!;
    }

    final writer = ByteWriter();
    writeVarUint(writer, 0);
    _writeStream(writer, _keyClockEncoder.toBytes());
    _writeStream(writer, _clientEncoder.toBytes());
    _writeStream(writer, _leftClockEncoder.toBytes());
    _writeStream(writer, _rightClockEncoder.toBytes());
    _writeStream(writer, _infoEncoder.toBytes());
    _writeStream(writer, _stringWriter.toBytes());
    _writeStream(writer, _parentInfoEncoder.toBytes());
    _writeStream(writer, _typeRefEncoder.toBytes());
    _writeStream(writer, _lenEncoder.toBytes());
    writer.writeBytes(super.toBytes());
    return _closedBytes ??= writer.toBytes();
  }
}

void _writeStream(ByteWriter writer, List<int> bytes) {
  string_codec.writeByteBuffer(writer, bytes);
}

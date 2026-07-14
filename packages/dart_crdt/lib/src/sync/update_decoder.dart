/// V1 and V2 update decoders.
library;

import 'dart:convert';

import '../binary/any_codec.dart';
import '../binary/any_value.dart';
import '../binary/byte_reader.dart';
import '../binary/rle_codec.dart';
import '../binary/string_buffer_codec.dart' as string_codec;
import '../binary/uint_opt_rle_codec.dart';
import '../binary/varint_codec.dart';
import '../metadata/id_set_codec.dart';
import '../structs/id.dart';

/// Thrown when an update stream contains invalid section or field data.
final class MalformedUpdateException implements FormatException {
  /// Creates an exception for malformed update bytes.
  const MalformedUpdateException({
    required this.offset,
    required this.reason,
  });

  @override
  final int offset;

  /// The reason decoding failed.
  final String reason;

  @override
  String get message => 'Malformed update at offset $offset: $reason.';

  @override
  Object? get source => null;

  @override
  String toString() => 'MalformedUpdateException: $message';
}

/// V1 update decoder over direct varint fields.
final class UpdateDecoderV1 extends IdSetDecoderV1 {
  /// Creates a V1 update decoder over [bytes].
  UpdateDecoderV1(super.bytes);

  /// Creates a V1 update decoder from [reader].
  UpdateDecoderV1.fromReader(super.reader) : super.fromReader();

  /// Reads a left-origin id.
  Id readLeftId() => Id.read(restReader);

  /// Reads a right-origin id.
  Id readRightId() => Id.read(restReader);

  /// Reads a client id.
  ClientId readClient() => readClientId(restReader);

  /// Reads an unsigned byte info field.
  int readInfo() => restReader.readByte();

  /// Reads a length-prefixed UTF-8 string.
  String readString() => string_codec.readString(restReader);

  /// Reads whether a parent reference is keyed by root name.
  bool readParentInfo() => readVarUint(restReader) == 1;

  /// Reads a shared type reference id.
  int readTypeRef() => readVarUint(restReader);

  /// Reads a struct length.
  int readLen() => readVarUint(restReader);

  /// Reads an arbitrary binary-capable value.
  AnyValue readAny() => readAnyValue(restReader);

  /// Reads a length-prefixed byte buffer.
  List<int> readBuf() => string_codec.readByteBuffer(restReader);

  /// Reads a legacy JSON string value.
  JsonValue readJson() {
    final str = readString();
    try {
      return JsonValue.fromObject(jsonDecode(str));
    } catch (_) {
      return JsonMap({});
    }
  }

  /// Reads a directly encoded key string.
  String readKey() => readString();
}

/// V2 update decoder over composed RLE streams and an unprefixed rest buffer.
final class UpdateDecoderV2 extends IdSetDecoderV2 {
  /// Creates a V2 update decoder over [bytes].
  factory UpdateDecoderV2(List<int> bytes) {
    return UpdateDecoderV2.fromReader(ByteReader(bytes));
  }

  /// Creates a V2 update decoder from [reader].
  factory UpdateDecoderV2.fromReader(ByteReader reader) {
    final featureFlag = readVarUint(reader);
    if (featureFlag != 0) {
      throw MalformedUpdateException(
        offset: 0,
        reason: 'unsupported feature flag $featureFlag',
      );
    }
    return UpdateDecoderV2._(
      featureFlag: featureFlag,
      keyClocks: string_codec.readByteBuffer(reader),
      clients: string_codec.readByteBuffer(reader),
      leftClocks: string_codec.readByteBuffer(reader),
      rightClocks: string_codec.readByteBuffer(reader),
      info: string_codec.readByteBuffer(reader),
      strings: string_codec.readByteBuffer(reader),
      parentInfo: string_codec.readByteBuffer(reader),
      typeRefs: string_codec.readByteBuffer(reader),
      lengths: string_codec.readByteBuffer(reader),
      rest: reader.readBytes(reader.remaining),
    );
  }

  UpdateDecoderV2._({
    required this.featureFlag,
    required List<int> keyClocks,
    required List<int> clients,
    required List<int> leftClocks,
    required List<int> rightClocks,
    required List<int> info,
    required List<int> strings,
    required List<int> parentInfo,
    required List<int> typeRefs,
    required List<int> lengths,
    required List<int> rest,
  })  : _keyClockDecoder = IntDiffOptRleDecoder(keyClocks),
        _clientDecoder = UintOptRleDecoder(clients),
        _leftClockDecoder = IntDiffOptRleDecoder(leftClocks),
        _rightClockDecoder = IntDiffOptRleDecoder(rightClocks),
        _infoDecoder = UintRleDecoder(info),
        _stringReader = ByteReader(strings),
        _parentInfoDecoder = UintRleDecoder(parentInfo),
        _typeRefDecoder = UintOptRleDecoder(typeRefs),
        _lenDecoder = UintOptRleDecoder(lengths),
        super.fromReader(ByteReader(rest));

  /// Feature flag read from the V2 update header.
  final int featureFlag;

  final IntDiffOptRleDecoder _keyClockDecoder;
  final UintOptRleDecoder _clientDecoder;
  final IntDiffOptRleDecoder _leftClockDecoder;
  final IntDiffOptRleDecoder _rightClockDecoder;
  final UintRleDecoder _infoDecoder;
  final ByteReader _stringReader;
  final UintRleDecoder _parentInfoDecoder;
  final UintOptRleDecoder _typeRefDecoder;
  final UintOptRleDecoder _lenDecoder;
  final List<String> _keys = <String>[];

  /// Reads a left-origin id.
  Id readLeftId() {
    return Id(client: readClient(), clock: Clock(_leftClockDecoder.read()));
  }

  /// Reads a right-origin id.
  Id readRightId() {
    return Id(client: readClient(), clock: Clock(_rightClockDecoder.read()));
  }

  /// Reads a client id.
  ClientId readClient() => ClientId(_clientDecoder.read());

  /// Reads an unsigned byte info field.
  int readInfo() {
    final info = _infoDecoder.read();
    RangeError.checkValueInInterval(info, 0, 255, 'info');
    return info;
  }

  /// Reads the next string from the shared string stream.
  String readString() => string_codec.readString(_stringReader);

  /// Reads whether a parent reference is keyed by root name.
  bool readParentInfo() {
    final value = _parentInfoDecoder.read();
    return switch (value) {
      0 => false,
      1 => true,
      _ => throw MalformedUpdateException(
          offset: restReader.offset,
          reason: 'parent info must be 0 or 1, got $value',
        ),
    };
  }

  /// Reads a shared type reference id.
  int readTypeRef() => _typeRefDecoder.read();

  /// Reads a struct length.
  int readLen() => _lenDecoder.read();

  /// Reads an arbitrary binary-capable value from the rest buffer.
  AnyValue readAny() => readAnyValue(restReader);

  /// Reads a length-prefixed byte buffer from the rest buffer.
  List<int> readBuf() => string_codec.readByteBuffer(restReader);

  /// Reads a legacy JSON value from the binary any-value rest buffer.
  AnyValue readJson() => readAny();

  /// Reads a cached key string.
  String readKey() {
    final keyClock = _keyClockDecoder.read();
    if (keyClock < _keys.length) {
      return _keys[keyClock];
    }
    if (keyClock != _keys.length) {
      throw MalformedUpdateException(
        offset: _stringReader.offset,
        reason: 'key clock $keyClock skipped ${_keys.length}',
      );
    }
    final key = readString();
    _keys.add(key);
    return key;
  }
}

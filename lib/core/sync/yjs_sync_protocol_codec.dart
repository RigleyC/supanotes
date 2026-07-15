import 'dart:typed_data';

import 'package:yjs_dart/yjs_dart.dart';

(int, int) _readVarUint(Uint8List data, int offset) {
  int value = 0;
  int shift = 0;
  int i = offset;
  while (i < data.length) {
    final byte = data[i];
    i++;
    value |= (byte & 127) << shift;
    shift += 7;
    if ((byte & 128) == 0) return (value, i - offset);
  }
  throw FormatException('Unexpected end of data in varint');
}

(int, Uint8List) _readVarUint8Array(Uint8List data, int offset) {
  final (length, lenSize) = _readVarUint(data, offset);
  final start = offset + lenSize;
  if (start + length > data.length) {
    throw FormatException('Unexpected end of data in varuint8array');
  }
  return (start + length, data.sublist(start, start + length));
}

List<int> _encodeVarUint(int value) {
  final bytes = <int>[];
  while (value > 127) {
    bytes.add((value & 127) | 128);
    value >>= 7;
  }
  bytes.add(value & 127);
  return bytes;
}

Uint8List _encodeMessage(int type, List<int> payload) {
  final typeBytes = _encodeVarUint(type);
  final payloadLen = _encodeVarUint(payload.length);
  final result = Uint8List(typeBytes.length + payloadLen.length + payload.length);
  result.setRange(0, typeBytes.length, typeBytes);
  result.setRange(typeBytes.length, typeBytes.length + payloadLen.length, payloadLen);
  result.setRange(typeBytes.length + payloadLen.length, result.length, payload);
  return result;
}

class YjsSyncProtocolCodec {
  static const int messageSyncStep1 = 0;
  static const int messageSyncStep2 = 1;
  static const int messageYjsUpdate = 2;

  static Uint8List encodeStep1(Doc doc) {
    final sv = encodeStateVector(doc);
    return _encodeMessage(messageSyncStep1, sv);
  }

  static Uint8List encodeStep2(Doc doc, Uint8List targetStateVector) {
    final missing = encodeStateAsUpdate(doc, targetStateVector);
    return _encodeMessage(messageSyncStep2, missing);
  }

  static Uint8List encodeUpdate(Uint8List update) {
    return _encodeMessage(messageYjsUpdate, update);
  }

  /// Parses a binary message into its type and raw payload bytes.
  /// Returns `(messageType, payloadBytes)`.
  static (int, Uint8List) decode(Uint8List data) {
    final (msgType, typeSize) = _readVarUint(data, 0);
    final (_, payload) = _readVarUint8Array(data, typeSize);
    return (msgType, payload);
  }
}

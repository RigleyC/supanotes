/// State-vector binary encoding and document/store helpers.
library;

import 'dart:collection';
import 'dart:typed_data';

import '../binary/byte_reader.dart';
import '../binary/byte_writer.dart';
import '../binary/varint_codec.dart';
import '../doc/doc.dart';
import '../metadata/id_set_codec.dart';
import '../structs/id.dart';
import '../structs/struct_store.dart';

/// Sync state keyed by client id with exclusive end clocks as values.
typedef StateVector = Map<ClientId, Clock>;

/// Thrown when a state-vector byte stream is structurally invalid.
final class MalformedStateVectorException implements FormatException {
  /// Creates an exception for malformed state-vector bytes.
  const MalformedStateVectorException({
    required this.offset,
    required this.reason,
  });

  @override
  final int offset;

  /// The reason decoding failed.
  final String reason;

  @override
  String get message => 'Malformed state vector at offset $offset: $reason.';

  @override
  Object? get source => null;

  @override
  String toString() => 'MalformedStateVectorException: $message';
}

/// Returns the current sync state for [document].
StateVector documentStateVector(Doc document) {
  return storeStateVector(document.store);
}

/// Returns the current sync state for [store].
StateVector storeStateVector(StructStore store) {
  return store.stateVector();
}

/// Writes [state] in canonical descending client-id order.
void writeStateVector(ByteWriter writer, StateVector state) {
  writeVarUint(writer, state.length);
  final clients = state.keys.toList()
    ..sort((left, right) => right.compareTo(left));
  for (final client in clients) {
    writeClientId(writer, client);
    writeClock(writer, state[client]!);
  }
}

/// Reads a state vector from [reader].
///
/// This consumes only the state-vector payload. Callers that decode a complete
/// message should verify [ByteReader.isDone] after this returns.
StateVector readStateVector(ByteReader reader) {
  final clientCount = readVarUint(reader);
  final state = _clientMap<Clock>();
  for (var clientIndex = 0; clientIndex < clientCount; clientIndex += 1) {
    final client = readClientId(reader);
    state[client] = readClock(reader);
  }
  return Map<ClientId, Clock>.unmodifiable(state);
}

/// Encodes [state] to immutable V1-compatible state-vector bytes.
Uint8List encodeStateVector(StateVector state) {
  final encoder = IdSetEncoderV1();
  writeStateVector(encoder.restWriter, state);
  return encoder.toBytes();
}

/// Encodes [state] with the V2 id-set encoder shell.
///
/// State vectors are stored in the direct rest stream, so this remains
/// byte-compatible with [encodeStateVector].
Uint8List encodeStateVectorV2(StateVector state) {
  final encoder = IdSetEncoderV2();
  writeStateVector(encoder.restWriter, state);
  return encoder.toBytes();
}

/// Encodes the current state vector for [document].
Uint8List encodeDocumentStateVector(Doc document) {
  return encodeStateVector(documentStateVector(document));
}

/// Encodes the current state vector for [document] using the V2 shell.
Uint8List encodeDocumentStateVectorV2(Doc document) {
  return encodeStateVectorV2(documentStateVector(document));
}

/// Encodes the current state vector for [store].
Uint8List encodeStoreStateVector(StructStore store) {
  return encodeStateVector(storeStateVector(store));
}

/// Encodes the current state vector for [store] using the V2 shell.
Uint8List encodeStoreStateVectorV2(StructStore store) {
  return encodeStateVectorV2(storeStateVector(store));
}

/// Decodes a complete V1-compatible state-vector byte stream.
StateVector decodeStateVector(List<int> bytes) {
  final decoder = IdSetDecoderV1(bytes);
  final state = readStateVector(decoder.restReader);
  if (!decoder.restReader.isDone) {
    throw MalformedStateVectorException(
      offset: decoder.restReader.offset,
      reason: '${decoder.restReader.remaining} trailing byte(s)',
    );
  }
  return state;
}

SplayTreeMap<ClientId, T> _clientMap<T>() {
  return SplayTreeMap<ClientId, T>((left, right) => left.compareTo(right));
}

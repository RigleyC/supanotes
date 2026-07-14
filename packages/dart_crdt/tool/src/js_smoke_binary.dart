part of '../js_smoke.dart';

Map<String, Object?> _binaryPrimitiveSmoke() {
  final unsigned = <int>[0, 1, 127, 128, 129, 16384, maxSafeInteger];
  final signed = <int>[
    -maxSafeInteger,
    -8192,
    -64,
    -1,
    0,
    1,
    63,
    64,
    8192,
    maxSafeInteger,
  ];
  final writer = ByteWriter();

  for (final value in unsigned) {
    writeVarUint(writer, value);
  }
  for (final value in signed) {
    writeVarInt(writer, value);
  }

  final reader = ByteReader(writer.toBytes());
  for (final expected in unsigned) {
    _expect(readVarUint(reader) == expected, 'varuint $expected');
  }
  for (final expected in signed) {
    _expect(readVarInt(reader) == expected, 'varint $expected');
  }
  _expect(reader.isDone, 'binary reader consumed all bytes');

  final state = <ClientId, Clock>{
    ClientId(1): Clock(7),
    ClientId(900719): Clock(3),
  };
  final decoded = decodeStateVector(encodeStateVector(state));
  _expect(_stateDigest(decoded) == _stateDigest(state), 'state vector');

  return <String, Object?>{
    'encodedBytes': writer.length,
    'valueCount': unsigned.length + signed.length,
    'stateVectorClients': decoded.length,
  };
}

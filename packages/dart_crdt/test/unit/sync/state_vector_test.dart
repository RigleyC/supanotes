import 'package:dart_crdt/src/binary/byte_reader.dart';
import 'package:dart_crdt/src/binary/byte_writer.dart';
import 'package:dart_crdt/src/binary/varint_codec.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/structs/abstract_struct.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:dart_crdt/src/structs/struct_store.dart';
import 'package:dart_crdt/src/sync/state_vector.dart';
import 'package:test/test.dart';

void main() {
  group('state vector codec', () {
    test('round-trips empty docs', () {
      final writer = ByteWriter();

      writeStateVector(writer, const {});

      expect(writer.toBytes(), [0]);
      expect(readStateVector(ByteReader(writer.toBytes())), isEmpty);
      expect(encodeStateVector(const {}), [0]);
      expect(decodeStateVector(const [0]), isEmpty);
    });

    test('writes clients in deterministic descending order', () {
      final state = {
        ClientId(1): Clock(5),
        ClientId(3): Clock(2),
        ClientId(2): Clock(4),
      };

      final encoded = encodeStateVector(state);

      expect(encoded, [3, 3, 2, 2, 4, 1, 5]);
      expect(decodeStateVector(encoded), state);
    });

    test('uses fixture bytes for multi-byte ids and clocks', () {
      final state = {
        ClientId(300): Clock(500),
        ClientId(1): Clock(0),
      };
      final expected = [
        2,
        ..._varUint(300),
        ..._varUint(500),
        1,
        0,
      ];

      expect(encodeStateVector(state), expected);
      expect(decodeStateVector(expected), state);
    });

    test('preserves V1-compatible bytes through the V2 shell', () {
      final state = {
        ClientId(7): Clock(8),
        ClientId(2): Clock(3),
      };

      expect(encodeStateVectorV2(state), encodeStateVector(state));
      expect(decodeStateVector(encodeStateVectorV2(state)), state);
    });

    test('rejects malformed complete byte streams', () {
      expect(
        () => decodeStateVector(const [1, 1]),
        throwsA(isA<TruncatedInputException>()),
      );
      expect(
        () => decodeStateVector(const [
          1,
          128,
          128,
          128,
          128,
          128,
          128,
          128,
          128,
        ]),
        throwsA(isA<MalformedVarintException>()),
      );
      expect(
        () => decodeStateVector(const [1, 1, 2, 0]),
        throwsA(isA<MalformedStateVectorException>()),
      );
    });
  });

  group('state vector helpers', () {
    test('reads and encodes store state', () {
      final store = StructStore()
        ..add(GC(id: _id(1, 0), length: 2))
        ..add(GC(id: _id(3, 0), length: 4))
        ..add(GC(id: _id(2, 0), length: 1));
      final expectedState = {
        ClientId(1): Clock(2),
        ClientId(2): Clock(1),
        ClientId(3): Clock(4),
      };

      expect(storeStateVector(store), expectedState);
      expect(encodeStoreStateVector(store), [3, 3, 4, 2, 1, 1, 2]);
      expect(encodeStoreStateVectorV2(store), encodeStoreStateVector(store));
    });

    test('reads and encodes document state', () {
      final doc = Doc(clientId: ClientId(9));
      doc.store
        ..add(GC(id: _id(4, 0), length: 3))
        ..add(GC(id: _id(5, 0), length: 2));
      final expectedState = {
        ClientId(4): Clock(3),
        ClientId(5): Clock(2),
      };

      expect(documentStateVector(doc), expectedState);
      expect(encodeDocumentStateVector(doc), [2, 5, 2, 4, 3]);
      expect(
        encodeDocumentStateVectorV2(doc),
        encodeDocumentStateVector(doc),
      );
    });
  });
}

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}

List<int> _varUint(int value) {
  final writer = ByteWriter();
  writeVarUint(writer, value);
  return writer.toBytes();
}

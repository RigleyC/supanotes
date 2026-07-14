import 'package:dart_crdt/src/binary/byte_reader.dart';
import 'package:dart_crdt/src/binary/byte_writer.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/structs/abstract_struct.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:dart_crdt/src/structs/struct_store.dart';
import 'package:dart_crdt/src/sync/state_vector.dart';
import 'package:test/test.dart';

void main() {
  group('state vector supplemental coverage', () {
    test('covers document/store helpers and malformed diagnostics', () {
      final doc = Doc();
      final store = StructStore()..add(GC(id: _id(2, 0), length: 3));
      final writer = ByteWriter();
      const malformed = MalformedStateVectorException(
        offset: 1,
        reason: 'bad',
      );

      doc.store.add(GC(id: _id(1, 0), length: 2));
      writeStateVector(writer, {ClientId(2): Clock(3), ClientId(1): Clock(2)});

      expect(documentStateVector(doc), {ClientId(1): Clock(2)});
      expect(storeStateVector(store), {ClientId(2): Clock(3)});
      expect(
        encodeDocumentStateVector(doc),
        encodeStateVector(documentStateVector(doc)),
      );
      expect(
        encodeDocumentStateVectorV2(doc),
        encodeStateVectorV2(documentStateVector(doc)),
      );
      expect(
        encodeStoreStateVector(store),
        encodeStateVector(storeStateVector(store)),
      );
      expect(
        encodeStoreStateVectorV2(store),
        encodeStateVectorV2(storeStateVector(store)),
      );
      expect(readStateVector(ByteReader(writer.toBytes())), {
        ClientId(1): Clock(2),
        ClientId(2): Clock(3),
      });
      expect(malformed.source, isNull);
      expect(malformed.toString(), contains(malformed.message));
      expect(
        () => decodeStateVector([0, 1]),
        throwsA(isA<MalformedStateVectorException>()),
      );
    });
  });
}

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}

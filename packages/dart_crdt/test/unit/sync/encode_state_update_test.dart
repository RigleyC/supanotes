import 'package:dart_crdt/src/binary/varint_codec.dart';
import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/metadata/id_set.dart';
import 'package:dart_crdt/src/structs/abstract_struct.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:dart_crdt/src/sync/block_set.dart';
import 'package:dart_crdt/src/sync/state_update.dart';
import 'package:dart_crdt/src/sync/state_vector.dart';
import 'package:dart_crdt/src/sync/update_decoder.dart';
import 'package:test/test.dart' hide Skip;

void main() {
  group('encodeStateAsUpdate', () {
    test('encodes empty documents', () {
      expect(encodeStateAsUpdate(Doc(clientId: ClientId(1))), [0, 0]);

      final v2 = UpdateDecoderV2(
        encodeStateAsUpdateV2(Doc(clientId: ClientId(1))),
      );
      expect(readVarUint(v2.restReader), 0);
      expect(readVarUint(v2.restReader), 0);
      expect(v2.restReader.remaining, 0);
    });

    test('encodes full V1 state with structs and derived deletes', () {
      final doc = Doc(clientId: ClientId(9));
      doc.store
        ..add(_item(2, 0, 'hi'))
        ..add(GC(id: _id(1, 0), length: 2));

      expect(
        encodeStateAsUpdate(doc),
        [
          2,
          1,
          2,
          0,
          4,
          1,
          4,
          114,
          111,
          111,
          116,
          2,
          104,
          105,
          1,
          1,
          0,
          0,
          2,
          1,
          1,
          1,
          0,
          2,
        ],
      );
      expect(
        createDeleteSetFromStore(doc.store),
        IdSet()..add(_id(1, 0), length: 2),
      );
    });

    test('encodes diffs against a target state vector', () {
      final doc = Doc(clientId: ClientId(9));
      doc.store.add(_item(1, 0, 'abc'));
      final target = encodeStateVector({ClientId(1): Clock(1)});

      expect(
        encodeStateAsUpdate(doc, target),
        [1, 1, 1, 1, 132, 1, 0, 2, 98, 99, 0],
      );
      expect(encodeStateAsUpdate(doc, encodeDocumentStateVector(doc)), [0, 0]);
    });

    test('includes pending delete sets and pending struct ranges', () {
      final doc = Doc(clientId: ClientId(9));
      doc.store
        ..addPendingDeleteSet(IdSet()..add(_id(4, 1), length: 2))
        ..addPendingStructs(BlockSet()..add(_id(3, 5), length: 4));

      expect(encodeStateAsUpdate(doc), [1, 1, 3, 5, 10, 4, 1, 4, 1, 1, 2]);

      final target = encodeStateVector({ClientId(3): Clock(6)});
      expect(
        encodeStateAsUpdate(doc, target),
        [1, 1, 3, 6, 10, 3, 1, 4, 1, 1, 2],
      );
    });
  });

  group('encodeStateAsUpdateV2', () {
    test('writes V2 client and struct fields to composed streams', () {
      final doc = Doc(clientId: ClientId(9));
      doc.store.add(_item(1, 0, 'hi'));
      final decoder = UpdateDecoderV2(encodeStateAsUpdateV2(doc));

      expect(readVarUint(decoder.restReader), 1);
      expect(readVarUint(decoder.restReader), 1);
      expect(decoder.readClient(), ClientId(1));
      expect(readVarUint(decoder.restReader), 0);
      expect(decoder.readInfo(), contentStringRef);
      expect(decoder.readParentInfo(), isTrue);
      expect(decoder.readString(), 'root');
      expect(decoder.readString(), 'hi');
      expect(readVarUint(decoder.restReader), 0);
      expect(decoder.restReader.remaining, 0);
    });
  });
}

Item _item(int client, int clock, String value) {
  return Item(
    id: _id(client, clock),
    parent: ItemParent(key: 'root'),
    content: ContentString(value),
  );
}

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}

import 'package:dart_crdt/src/binary/any_value.dart';
import 'package:dart_crdt/src/binary/byte_reader.dart';
import 'package:dart_crdt/src/binary/byte_writer.dart';
import 'package:dart_crdt/src/binary/string_buffer_codec.dart';
import 'package:dart_crdt/src/binary/varint_codec.dart';
import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/structs/abstract_struct.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:dart_crdt/src/structs/struct_binary.dart';
import 'package:test/test.dart' hide Skip;

void main() {
  group('Struct binary content round-trips', () {
    test('reads and writes every current content variant', () {
      final variants = <AbstractContent>[
        ContentAny([const JsonString('a'), JsonNumber(2)]),
        ContentJson([const JsonString('j'), const JsonBool(true)]),
        ContentBinary([1, 2, 3]),
        ContentString('hi'),
        ContentEmbed({'k': 'v'}),
        ContentFormat(key: 'bold', value: true),
        ContentType(
          const SharedTypePlaceholder(kind: SharedTypeKind.text, name: 'body'),
        ),
        ContentDocument(
          guid: 'doc-1',
          collectionId: 'team',
          meta: const JsonString('draft'),
          autoLoad: true,
        ),
        ContentDeleted(3),
      ];

      for (final content in variants) {
        final item = Item(
          id: _id(1, 0),
          parent: ItemParent(key: 'root'),
          content: content,
        );
        final decoded = decodeStructV1(
          encodeStructV1(item),
          id: item.id,
          context: StructReadContext(),
        );

        expect(decoded, isA<Item>());
        expect((decoded as Item).content, content);
        expect(decoded.parent?.key, 'root');
      }
    });

    test('uses the same struct facade for V2 until compressed streams exist',
        () {
      final item = Item(
        id: _id(1, 0),
        parent: ItemParent(key: 'root'),
        content: ContentString('v2'),
      );

      final decoded = decodeStructV2(
        encodeStructV2(item),
        id: item.id,
        context: StructReadContext(),
      );

      expect(decoded, isA<Item>());
      expect((decoded as Item).content, ContentString('v2'));
    });
  });

  group('Struct binary info flags and refs', () {
    test('round-trips root parent keys and parent sub-keys', () {
      final item = Item(
        id: _id(2, 0),
        parent: ItemParent(key: 'attrs'),
        parentSub: 'title',
        content: ContentString('ok'),
      );
      final bytes = encodeStructV1(item);
      final decoded = decodeStructV1(
        bytes,
        id: item.id,
        context: StructReadContext(),
      ) as Item;

      expect(bytes.first, contentStringRef | 0x20);
      expect(decoded.parent?.key, 'attrs');
      expect(decoded.parentSub, 'title');
      expect(decoded.content, ContentString('ok'));
    });

    test('round-trips origin and right-origin flags with fallback parent', () {
      final parent = ItemParent(key: 'root');
      final item = Item(
        id: _id(3, 5),
        origin: _id(3, 4),
        rightOrigin: _id(4, 1),
        parent: parent,
        content: ContentString('x'),
      );
      final bytes = encodeStructV1(item);
      final decoded = decodeStructV1(
        bytes,
        id: item.id,
        context: StructReadContext(fallbackParent: parent),
      ) as Item;

      expect(bytes.first, contentStringRef | 0x80 | 0x40);
      expect(decoded.origin, _id(3, 4));
      expect(decoded.rightOrigin, _id(4, 1));
      expect(decoded.parent, same(parent));
    });

    test('round-trips GC and Skip refs', () {
      final gc = decodeStructV1(
        encodeStructV1(GC(id: _id(1, 0), length: 4)),
        id: _id(1, 0),
        context: StructReadContext(),
      );
      final skip = decodeStructV1(
        encodeStructV1(Skip(id: _id(2, 3), length: 2)),
        id: _id(2, 3),
        context: StructReadContext(),
      );

      expect(gc, isA<GC>());
      expect(gc.length, 4);
      expect(skip, isA<Skip>());
      expect(skip.length, 2);
      expect(encodeStructV1(gc).first, structGcRefNumber);
      expect(encodeStructV1(skip).first, structSkipRefNumber);
    });
  });

  group('Struct binary malformed input', () {
    test('rejects truncated and trailing struct payloads', () {
      expect(
        () => readStructV1(
          ByteReader([contentStringRef]),
          id: _id(1, 0),
          context: StructReadContext(),
        ),
        throwsA(isA<TruncatedInputException>()),
      );
      expect(
        () => decodeStructV1(
          [structGcRefNumber, 1, 99],
          id: _id(1, 0),
          context: StructReadContext(),
        ),
        throwsA(isA<MalformedStructException>()),
      );
    });

    test('rejects missing fallback parent for linked items', () {
      expect(
        () => decodeStructV1(
          [contentStringRef | 0x80, 1, 0, 1, 120],
          id: _id(1, 1),
          context: StructReadContext(),
        ),
        throwsA(isA<MalformedStructException>()),
      );
    });

    test('rejects unknown content and shared type refs', () {
      final unknownContent = ByteWriter()
        ..writeByte(31)
        ..writeStringPayload('root');
      final unknownType = ByteWriter()
        ..writeByte(contentTypeRef)
        ..writeStringPayload('root')
        ..writeVarUintPayload(99)
        ..writeStringPayload('bad');

      expect(
        () => decodeStructV1(
          unknownContent.toBytes(),
          id: _id(1, 0),
          context: StructReadContext(),
        ),
        throwsA(isA<MalformedContentException>()),
      );
      expect(
        () => decodeStructV1(
          unknownType.toBytes(),
          id: _id(1, 0),
          context: StructReadContext(),
        ),
        throwsA(isA<MalformedContentException>()),
      );
    });
  });
}

extension on ByteWriter {
  void writeStringPayload(String value) => writeString(this, value);

  void writeVarUintPayload(int value) => writeVarUint(this, value);
}

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}

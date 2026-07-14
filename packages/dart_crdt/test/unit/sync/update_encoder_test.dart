import 'package:dart_crdt/src/binary/any_codec.dart';
import 'package:dart_crdt/src/binary/any_value.dart';
import 'package:dart_crdt/src/binary/byte_reader.dart';
import 'package:dart_crdt/src/binary/rle_codec.dart';
import 'package:dart_crdt/src/binary/string_buffer_codec.dart';
import 'package:dart_crdt/src/binary/uint_opt_rle_codec.dart';
import 'package:dart_crdt/src/binary/varint_codec.dart';
import 'package:dart_crdt/src/metadata/id_set_codec.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:dart_crdt/src/sync/update_encoder.dart';
import 'package:test/test.dart';

void main() {
  group('IdSet update encoders', () {
    test('write V1 absolute clocks and V2 clock diffs', () {
      final v1 = IdSetEncoderV1()
        ..writeIdSetClock(Clock(10))
        ..writeIdSetLen(3)
        ..writeIdSetClock(Clock(20))
        ..writeIdSetLen(1);
      final v2 = IdSetEncoderV2()
        ..writeIdSetClock(Clock(10))
        ..writeIdSetLen(3)
        ..writeIdSetClock(Clock(20))
        ..writeIdSetLen(1);

      expect(v1.toBytes(), [10, 3, 20, 1]);
      expect(v2.toBytes(), [10, 2, 7, 0]);
      expect(
        () => IdSetEncoderV2()
          ..writeIdSetClock(Clock(5))
          ..writeIdSetClock(Clock(4)),
        throwsRangeError,
      );
      expect(() => IdSetEncoderV2().writeIdSetLen(0), throwsRangeError);
    });
  });

  group('UpdateEncoderV1', () {
    test('starts empty and writes deterministic direct fields', () {
      final encoder = UpdateEncoderV1();

      expect(encoder.toBytes(), isEmpty);

      final filled = UpdateEncoderV1()
        ..writeLeftId(_id(2, 3))
        ..writeRightId(_id(4, 5))
        ..writeClient(ClientId(6))
        ..writeInfo(7)
        ..writeString('a')
        ..writeParentInfo(true)
        ..writeTypeRef(8)
        ..writeLen(9)
        ..writeBuf([1, 2])
        ..writeKey('k');

      expect(
        filled.toBytes(),
        [2, 3, 4, 5, 6, 7, 1, 97, 1, 8, 9, 2, 1, 2, 1, 107],
      );
    });

    test('writes legacy JSON as a length-prefixed JSON string', () {
      final encoder = UpdateEncoderV1()
        ..writeJson(JsonMap({'ok': const JsonBool(true)}));
      final reader = ByteReader(encoder.toBytes());

      expect(readString(reader), '{"ok":true}');
      expect(reader.remaining, 0);
    });
  });

  group('UpdateEncoderV2', () {
    test('starts with feature flag and empty streams', () {
      expect(UpdateEncoderV2().toBytes(), [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
    });

    test('composes RLE streams and appends rest buffer', () {
      final encoder = UpdateEncoderV2()
        ..writeKey('title')
        ..writeKey('title')
        ..writeLeftId(_id(7, 3))
        ..writeRightId(_id(7, 5))
        ..writeInfo(9)
        ..writeInfo(9)
        ..writeString('value')
        ..writeParentInfo(true)
        ..writeParentInfo(true)
        ..writeTypeRef(4)
        ..writeLen(12)
        ..writeAny(const JsonString('tail'))
        ..writeBuf([8, 9]);

      final sections = _readV2Sections(encoder.toBytes());

      expect(sections.featureFlag, 0);
      expect(IntDiffOptRleDecoder(sections.keyClocks).readAll(2), [0, 0]);
      expect(UintOptRleDecoder(sections.clients).readAll(2), [7, 7]);
      expect(IntDiffOptRleDecoder(sections.leftClocks).readAll(1), [3]);
      expect(IntDiffOptRleDecoder(sections.rightClocks).readAll(1), [5]);
      expect(UintRleDecoder(sections.info).readAll(2), [9, 9]);
      expect(UintRleDecoder(sections.parentInfo).readAll(2), [1, 1]);
      expect(UintOptRleDecoder(sections.typeRefs).readAll(1), [4]);
      expect(UintOptRleDecoder(sections.lengths).readAll(1), [12]);

      final strings = ByteReader(sections.strings);
      expect(readString(strings), 'title');
      expect(readString(strings), 'value');
      expect(strings.remaining, 0);

      final rest = ByteReader(sections.rest);
      expect(readAnyValue(rest), const JsonString('tail'));
      expect(readByteBuffer(rest), [8, 9]);
      expect(rest.remaining, 0);
    });

    test('writes legacy JSON using binary any-value encoding', () {
      final encoder = UpdateEncoderV2()
        ..writeJson(AnyMap({'ok': const JsonBool(true)}));
      final reader = ByteReader(_readV2Sections(encoder.toBytes()).rest);

      expect(readAnyValue(reader), AnyMap({'ok': const JsonBool(true)}));
      expect(reader.remaining, 0);
    });
  });
}

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}

_V2Sections _readV2Sections(List<int> bytes) {
  final reader = ByteReader(bytes);
  return _V2Sections(
    featureFlag: readVarUint(reader),
    keyClocks: readByteBuffer(reader),
    clients: readByteBuffer(reader),
    leftClocks: readByteBuffer(reader),
    rightClocks: readByteBuffer(reader),
    info: readByteBuffer(reader),
    strings: readByteBuffer(reader),
    parentInfo: readByteBuffer(reader),
    typeRefs: readByteBuffer(reader),
    lengths: readByteBuffer(reader),
    rest: reader.readBytes(reader.remaining),
  );
}

final class _V2Sections {
  const _V2Sections({
    required this.featureFlag,
    required this.keyClocks,
    required this.clients,
    required this.leftClocks,
    required this.rightClocks,
    required this.info,
    required this.strings,
    required this.parentInfo,
    required this.typeRefs,
    required this.lengths,
    required this.rest,
  });

  final int featureFlag;
  final List<int> keyClocks;
  final List<int> clients;
  final List<int> leftClocks;
  final List<int> rightClocks;
  final List<int> info;
  final List<int> strings;
  final List<int> parentInfo;
  final List<int> typeRefs;
  final List<int> lengths;
  final List<int> rest;
}

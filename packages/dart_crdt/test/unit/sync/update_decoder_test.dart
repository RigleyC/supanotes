import 'package:dart_crdt/src/binary/any_value.dart';
import 'package:dart_crdt/src/binary/byte_writer.dart';
import 'package:dart_crdt/src/binary/string_buffer_codec.dart';
import 'package:dart_crdt/src/binary/uint_opt_rle_codec.dart';
import 'package:dart_crdt/src/metadata/id_set_codec.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:dart_crdt/src/sync/update_decoder.dart';
import 'package:dart_crdt/src/sync/update_encoder.dart';
import 'package:test/test.dart';

void main() {
  group('IdSet update decoders', () {
    test('read V1 absolute clocks and V2 clock diffs', () {
      final v1 = IdSetDecoderV1([10, 3, 20, 1]);
      final v2 = IdSetDecoderV2([10, 2, 7, 0]);

      expect(v1.readIdSetClock(), Clock(10));
      expect(v1.readIdSetLen(), 3);
      expect(v1.readIdSetClock(), Clock(20));
      expect(v1.readIdSetLen(), 1);

      expect(v2.readIdSetClock(), Clock(10));
      expect(v2.readIdSetLen(), 3);
      expect(v2.readIdSetClock(), Clock(20));
      expect(v2.readIdSetLen(), 1);

      final reset = IdSetDecoderV2([10, 2, 10, 2])
        ..readIdSetClock()
        ..readIdSetLen()
        ..resetIdSetCurVal()
        ..readIdSetClock();
      expect(reset.readIdSetLen(), 3);
    });
  });

  group('UpdateDecoderV1', () {
    test('round-trips direct fields with the V1 encoder', () {
      final encoder = UpdateEncoderV1()
        ..writeLeftId(_id(2, 3))
        ..writeRightId(_id(4, 5))
        ..writeClient(ClientId(6))
        ..writeInfo(7)
        ..writeString('a')
        ..writeParentInfo(true)
        ..writeTypeRef(8)
        ..writeLen(9)
        ..writeAny(const JsonString('any'))
        ..writeBuf([1, 2])
        ..writeJson(JsonMap({'ok': const JsonBool(true)}))
        ..writeKey('k');
      final decoder = UpdateDecoderV1(encoder.toBytes());

      expect(decoder.readLeftId(), _id(2, 3));
      expect(decoder.readRightId(), _id(4, 5));
      expect(decoder.readClient(), ClientId(6));
      expect(decoder.readInfo(), 7);
      expect(decoder.readString(), 'a');
      expect(decoder.readParentInfo(), isTrue);
      expect(decoder.readTypeRef(), 8);
      expect(decoder.readLen(), 9);
      expect(decoder.readAny(), const JsonString('any'));
      expect(decoder.readBuf(), [1, 2]);
      expect(decoder.readJson(), JsonMap({'ok': const JsonBool(true)}));
      expect(decoder.readKey(), 'k');
      expect(decoder.restReader.remaining, 0);
    });

    test('reports malformed direct streams', () {
      expect(() => UpdateDecoderV1([128]).readLen(), throwsA(isA<Exception>()));
      expect(() => UpdateDecoderV1([]).readInfo(), throwsA(isA<Exception>()));
    });
  });

  group('UpdateDecoderV2', () {
    test('parses empty encoder output and feature flag', () {
      final decoder = UpdateDecoderV2(UpdateEncoderV2().toBytes());

      expect(decoder.featureFlag, 0);
      expect(decoder.restReader.remaining, 0);
      expect(
        () => UpdateDecoderV2([1]),
        throwsA(isA<MalformedUpdateException>()),
      );
      expect(() => UpdateDecoderV2([]), throwsA(isA<Exception>()));
    });

    test('round-trips composed streams with the V2 encoder', () {
      final encoder = UpdateEncoderV2()
        ..writeKey('title')
        ..writeKey('title')
        ..writeLeftId(_id(7, 3))
        ..writeRightId(_id(7, 5))
        ..writeInfo(9)
        ..writeInfo(9)
        ..writeString('value')
        ..writeParentInfo(true)
        ..writeParentInfo(false)
        ..writeTypeRef(4)
        ..writeLen(12)
        ..writeAny(const JsonString('tail'))
        ..writeBuf([8, 9])
        ..writeJson(AnyMap({'ok': const JsonBool(true)}))
        ..writeIdSetClock(Clock(10))
        ..writeIdSetLen(3);
      final decoder = UpdateDecoderV2(encoder.toBytes());

      expect(decoder.readKey(), 'title');
      expect(decoder.readKey(), 'title');
      expect(decoder.readLeftId(), _id(7, 3));
      expect(decoder.readRightId(), _id(7, 5));
      expect(decoder.readInfo(), 9);
      expect(decoder.readInfo(), 9);
      expect(decoder.readString(), 'value');
      expect(decoder.readParentInfo(), isTrue);
      expect(decoder.readParentInfo(), isFalse);
      expect(decoder.readTypeRef(), 4);
      expect(decoder.readLen(), 12);
      expect(decoder.readAny(), const JsonString('tail'));
      expect(decoder.readBuf(), [8, 9]);
      expect(decoder.readJson(), AnyMap({'ok': const JsonBool(true)}));
      expect(decoder.readIdSetClock(), Clock(10));
      expect(decoder.readIdSetLen(), 3);
      expect(decoder.restReader.remaining, 0);
    });

    test('rejects malformed key clocks and truncated sections', () {
      expect(
        () => UpdateDecoderV2(_v2WithSkippedKey()).readKey(),
        throwsA(isA<MalformedUpdateException>()),
      );
      expect(
        () => UpdateDecoderV2([0, 1]),
        throwsA(isA<Exception>()),
      );
    });
  });
}

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}

List<int> _v2WithSkippedKey() {
  final keyClocks = IntDiffOptRleEncoder()..write(2);
  final writer = ByteWriter()..writeByte(0);
  writeByteBuffer(writer, keyClocks.toBytes());
  for (var index = 0; index < 8; index += 1) {
    writeByteBuffer(writer, const <int>[]);
  }
  return writer.toBytes();
}

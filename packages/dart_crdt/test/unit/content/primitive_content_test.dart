import 'dart:typed_data';

import 'package:dart_crdt/src/binary/any_value.dart';
import 'package:dart_crdt/src/binary/byte_writer.dart';
import 'package:dart_crdt/src/content/content.dart';
import 'package:test/test.dart';

void main() {
  group('collection content', () {
    test('copies, splices, merges, extracts, and writes arbitrary values', () {
      final content = ContentAny.fromObjects(['a', 2, true]);
      final copy = content.copy();
      final right = content.splice(1);
      final writer = ByteWriter();

      content.writeWithRef(writer);

      expect(copy, ContentAny.fromObjects(['a', 2, true]));
      expect(content.content, ['a']);
      expect(right.content, [2, true]);
      expect(content.mergeWith(right), isTrue);
      expect(content.content, ['a', 2, true]);
      expect(content.ref, contentAnyRef);
      expect(writer.toBytes(), [8, 1, 5, 1, 97]);
    });

    test('handles JSON values, empty arrays, and binary writes', () {
      final content = ContentJson.fromObjects(['x', null]);
      final empty = ContentJson(const <JsonValue>[]);
      final writer = ByteWriter();

      content.writeWithRef(writer);

      expect(content.length, 2);
      expect(empty.length, 0);
      expect(empty.content, isEmpty);
      expect(empty.mergeWith(ContentJson.fromObjects([1])), isTrue);
      expect(empty.content, [1]);
      expect(writer.toBytes(), [
        2,
        2,
        3,
        34,
        120,
        34,
        4,
        110,
        117,
        108,
        108,
      ]);
    });

    test('splits strings without leaving dangling surrogate pairs', () {
      final content = ContentString('a😀b');
      final right = content.splice(2);

      expect(content.content, ['a', '\ufffd']);
      expect(right.content, ['\ufffd', 'b']);
      expect(content.mergeWith(right), isTrue);
      expect(content.value, 'a\ufffd\ufffdb');
      expect(ContentString('').content, isEmpty);
    });
  });

  group('scalar content', () {
    test('writes binary, embed, and format payloads with stable refs', () {
      final binaryWriter = ByteWriter();
      final embedWriter = ByteWriter();
      final formatWriter = ByteWriter();

      ContentBinary([1, 2, 3]).writeWithRef(binaryWriter);
      ContentEmbed({'kind': 'image'}).writeWithRef(embedWriter);
      ContentFormat(key: 'bold', value: true).writeWithRef(formatWriter);

      expect(binaryWriter.toBytes(), [3, 3, 1, 2, 3]);
      expect(embedWriter.toBytes(), [
        5,
        7,
        1,
        4,
        107,
        105,
        110,
        100,
        5,
        5,
        105,
        109,
        97,
        103,
        101,
      ]);
      expect(formatWriter.toBytes(), [6, 4, 98, 111, 108, 100, 2]);
    });

    test('uses non-countable deleted and format semantics', () {
      final target = _LifecycleTarget();
      final deleted = ContentDeleted(5);
      final format = ContentFormat(key: 'italic', value: true);
      final right = deleted.splice(2);
      final writer = ByteWriter();

      deleted
        ..integrate(target)
        ..mergeWith(right)
        ..writeWithRef(writer, offset: 1, offsetEnd: 2);
      format.integrate(target);

      expect(deleted.isCountable, isFalse);
      expect(format.isCountable, isFalse);
      expect(deleted.length, 5);
      expect(target.deletedLengths, [2]);
      expect(target.formatCleared, isTrue);
      expect(target.hasFormatting, isTrue);
      expect(writer.toBytes(), [1, 2]);
    });

    test('defensively copies binary data and rejects unsupported splits', () {
      final bytes = Uint8List.fromList([4, 5]);
      final content = ContentBinary(bytes);

      bytes[0] = 9;

      expect(content.content.single, Uint8List.fromList([4, 5]));
      expect(content.copy(), content);
      expect(content.mergeWith(ContentBinary([6])), isFalse);
      expect(() => content.splice(1), throwsUnsupportedError);
      expect(() => ContentDeleted(0), throwsRangeError);
    });
  });
}

final class _LifecycleTarget implements ContentLifecycleTarget {
  final deletedLengths = <int>[];
  bool formatCleared = false;
  bool hasFormatting = false;

  @override
  void clearFormattingCache() {
    formatCleared = true;
  }

  @override
  void markDeleted(int length) {
    deletedLengths.add(length);
  }

  @override
  void markHasFormatting() {
    hasFormatting = true;
  }
}

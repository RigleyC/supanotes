import 'package:dart_crdt/src/binary/any_codec.dart';
import 'package:dart_crdt/src/binary/any_value.dart';
import 'package:dart_crdt/src/binary/byte_reader.dart';
import 'package:dart_crdt/src/binary/byte_writer.dart';
import 'package:dart_crdt/src/binary/string_buffer_codec.dart';
import 'package:dart_crdt/src/binary/varint_codec.dart';
import 'package:dart_crdt/src/content/content.dart';
import 'package:test/test.dart';

void main() {
  group('content supplemental coverage', () {
    test('covers scalar content identity and unsupported operations', () {
      final binary = ContentBinary([1, 2]);
      final embed = ContentEmbed({'kind': 'image'});
      final format = ContentFormat(key: 'bold', value: true);
      final deleted = ContentDeleted(2);

      expect(binary.content.single, [1, 2]);
      expect(binary.hashCode, ContentBinary([1, 2]).hashCode);
      expect(binary == ContentBinary([2, 1]), isFalse);
      expect(() => ContentBinary([256]), throwsRangeError);
      expect(embed.copy(), embed);
      expect(embed.mergeWith(ContentString('x')), isFalse);
      expect(() => embed.splice(1), throwsUnsupportedError);
      expect(embed.hashCode, ContentEmbed({'kind': 'image'}).hashCode);
      expect(format.copy(), format);
      expect(format.mergeWith(ContentDeleted(1)), isFalse);
      expect(() => format.splice(1), throwsUnsupportedError);
      expect(format.hashCode, ContentFormat(key: 'bold', value: true).hashCode);
      expect(deleted.mergeWith(ContentString('x')), isFalse);
      expect(deleted.hashCode, ContentDeleted(2).hashCode);
    });

    test('covers collection content identity and encoded slices', () {
      final any = ContentAny.fromObjects(['a', 1]);
      final json = ContentJson.fromObjects(['a', true]);
      final string = ContentString('abcd');
      final anyWriter = ByteWriter();
      final jsonWriter = ByteWriter();
      final stringWriter = ByteWriter();

      any.write(anyWriter, offset: 1);
      json.write(jsonWriter, offset: 1);
      string.write(stringWriter, offset: 1, offsetEnd: 1);

      expect(any.copy(), any);
      expect(any.mergeWith(ContentString('x')), isFalse);
      expect(any.hashCode, ContentAny.fromObjects(['a', 1]).hashCode);
      expect(json.copy(), json);
      expect(json.mergeWith(ContentAny.fromObjects(['x'])), isFalse);
      expect(json.hashCode, ContentJson.fromObjects(['a', true]).hashCode);
      expect(string.copy(), string);
      expect(string.mergeWith(ContentAny.fromObjects(['x'])), isFalse);
      expect(string.hashCode, ContentString('abcd').hashCode);
      expect(anyWriter.toBytes(), [1, 3, 1]);
      expect(jsonWriter.toBytes(), [1, 4, 116, 114, 117, 101]);
      expect(stringWriter.toBytes(), [2, 98, 99]);
      expect(
        () => string.encodedLength(offset: 3, offsetEnd: 3),
        throwsRangeError,
      );
    });

    test('covers content type lifecycle and malformed codec branches', () {
      final placeholder = const SharedTypePlaceholder(
        kind: SharedTypeKind.xmlHook,
        name: 'hook',
      );
      final content = ContentType(placeholder);
      final nestedTarget = _NestedTarget();
      final plainTarget = _PlainTarget();
      final writer = ByteWriter();

      content
        ..integrate(nestedTarget)
        ..delete(nestedTarget)
        ..gc(nestedTarget)
        ..write(writer);

      expect(placeholder.copy(), placeholder);
      expect(placeholder.toString(), 'xmlHook:hook');
      expect(content.copy(), content);
      expect(content.content, [placeholder]);
      expect(content.hashCode, ContentType(placeholder).hashCode);
      expect(content.mergeWith(ContentType(placeholder)), isFalse);
      expect(() => content.splice(1), throwsUnsupportedError);
      expect(() => content.integrate(plainTarget), throwsStateError);
      expect(() => content.delete(plainTarget), throwsStateError);
      expect(() => content.gc(plainTarget), throwsStateError);
      expect(nestedTarget.integrated, [placeholder]);
      expect(nestedTarget.deleted, [placeholder]);
      expect(nestedTarget.gced, [placeholder]);
      expect(
        readContentByRef(ByteReader(writer.toBytes()), contentTypeRef),
        content,
      );
      expect(
        const MalformedContentException(offset: 1, reason: 'bad').toString(),
        contains('bad'),
      );
      expect(
        const MalformedContentException(offset: 1, reason: 'bad').source,
        isNull,
      );
      expect(
        () => readContentByRef(ByteReader(const <int>[]), 99),
        throwsA(isA<MalformedContentException>()),
      );
      expect(
        () => readContentByRef(ByteReader(_encodedTypeRef(99)), contentTypeRef),
        throwsA(isA<MalformedContentException>()),
      );
    });

    test('covers document content option validation branches', () {
      expect(
        () => readContentByRef(
          ByteReader(_encodedDocumentOptions(const JsonString('bad'))),
          contentDocumentRef,
        ),
        throwsA(isA<MalformedContentException>()),
      );
      expect(
        () => readContentByRef(
          ByteReader(
            _encodedDocumentOptions(AnyMap({'collectionId': JsonNumber(1)})),
          ),
          contentDocumentRef,
        ),
        throwsA(isA<MalformedContentException>()),
      );
      expect(
        () => readContentByRef(
          ByteReader(
            _encodedDocumentOptions(
              AnyMap({'autoLoad': const JsonString('yes')}),
            ),
          ),
          contentDocumentRef,
        ),
        throwsA(isA<MalformedContentException>()),
      );
      expect(
        readContentByRef(
          ByteReader(
            _encodedDocumentOptions(
              AnyMap({
                'collectionId': const JsonString('c'),
                'autoLoad': const JsonBool(true),
                'shouldLoad': const JsonBool(true),
              }),
            ),
          ),
          contentDocumentRef,
        ),
        isA<ContentDocument>(),
      );
    });
  });
}

List<int> _encodedTypeRef(int ref) {
  final writer = ByteWriter();
  writeVarUint(writer, ref);
  return writer.toBytes();
}

List<int> _encodedDocumentOptions(AnyValue options) {
  final writer = ByteWriter();
  writeString(writer, 'doc');
  writeAnyValue(writer, options);
  return writer.toBytes();
}

final class _PlainTarget implements ContentLifecycleTarget {
  @override
  void clearFormattingCache() {}

  @override
  void markDeleted(int length) {}

  @override
  void markHasFormatting() {}
}

final class _NestedTarget implements NestedContentLifecycleTarget {
  final integrated = <SharedTypePlaceholder>[];
  final deleted = <SharedTypePlaceholder>[];
  final gced = <SharedTypePlaceholder>[];

  @override
  void addSubdocument(Subdocument document) {}

  @override
  void clearFormattingCache() {}

  @override
  void deleteSharedType(SharedTypePlaceholder sharedType) {
    deleted.add(sharedType);
  }

  @override
  void gcSharedType(SharedTypePlaceholder sharedType) {
    gced.add(sharedType);
  }

  @override
  void integrateSharedType(SharedTypePlaceholder sharedType) {
    integrated.add(sharedType);
  }

  @override
  void loadSubdocument(Subdocument document) {}

  @override
  void markDeleted(int length) {}

  @override
  void markHasFormatting() {}

  @override
  void removeSubdocument(Subdocument document) {}
}

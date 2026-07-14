import 'package:dart_crdt/src/binary/any_value.dart';
import 'package:dart_crdt/src/binary/byte_writer.dart';
import 'package:dart_crdt/src/content/content.dart';
import 'package:test/test.dart';

void main() {
  group('ContentDocument', () {
    test('copies as a detached document placeholder', () {
      final original = ContentDocument(
        guid: 'doc-1',
        collectionId: 'team',
        meta: const JsonString('draft'),
        autoLoad: true,
      );
      final copy = original.copy();

      expect(copy, original);
      expect(identical(copy.document, original.document), isFalse);
      expect(copy.document.guid, 'doc-1');
      expect(copy.document.collectionId, 'team');
      expect(copy.document.shouldLoad, isTrue);
      expect(copy.content, [copy.document]);
    });

    test('integrates, loads, deletes, and enforces ownership', () async {
      final target = _NestedTarget();
      final document = Subdocument(guid: 'doc-2', shouldLoad: true);
      final content = ContentDocument.fromDocument(document);
      final conflicting = ContentDocument.fromDocument(document);

      content.integrate(target);
      await document.load();
      content.delete(target);
      conflicting.integrate(target);

      expect(target.added, [document, document]);
      expect(target.loaded, [document]);
      expect(target.removed, [document]);
      expect(document.isLoaded, isTrue);
      expect(document.isAttached, isTrue);
      expect(
        () => content.integrate(target),
        throwsA(isA<StateError>()),
      );
      expect(() => content.splice(1), throwsUnsupportedError);
    });

    test('writes document refs with neutral options', () {
      final writer = ByteWriter();

      ContentDocument(guid: 'doc-1').writeWithRef(writer);

      expect(writer.toBytes(), [9, 5, 100, 111, 99, 45, 49, 7, 0]);
    });
  });

  group('ContentType', () {
    test('copies, extracts, and blocks merge/split for shared types', () {
      final content = ContentType(
        const SharedTypePlaceholder(
          kind: SharedTypeKind.text,
          name: 'body',
        ),
      );
      final copy = content.copy();

      expect(copy, content);
      expect(identical(copy.sharedType, content.sharedType), isFalse);
      expect(content.content, [content.sharedType]);
      expect(content.isCountable, isTrue);
      expect(content.mergeWith(copy), isFalse);
      expect(() => content.splice(1), throwsUnsupportedError);
    });

    test('emits lifecycle placeholders and binary type references', () {
      final target = _NestedTarget();
      final writer = ByteWriter();
      final sharedType = const SharedTypePlaceholder(
        kind: SharedTypeKind.map,
        name: 'attrs',
      );
      final content = ContentType(sharedType);

      content
        ..integrate(target)
        ..delete(target)
        ..gc(target)
        ..writeWithRef(writer);

      expect(target.integratedTypes, [sharedType]);
      expect(target.deletedTypes, [sharedType]);
      expect(target.gcTypes, [sharedType]);
      expect(writer.toBytes(), [7, 1, 5, 97, 116, 116, 114, 115]);
    });

    test('requires nested lifecycle targets for hooks', () {
      final content = ContentType(
        const SharedTypePlaceholder(kind: SharedTypeKind.array),
      );

      expect(
        () => content.integrate(_PrimitiveTarget()),
        throwsA(isA<StateError>()),
      );
    });
  });
}

final class _NestedTarget implements NestedContentLifecycleTarget {
  final added = <Subdocument>[];
  final loaded = <Subdocument>[];
  final removed = <Subdocument>[];
  final integratedTypes = <SharedTypePlaceholder>[];
  final deletedTypes = <SharedTypePlaceholder>[];
  final gcTypes = <SharedTypePlaceholder>[];
  final deletedLengths = <int>[];
  bool formatCleared = false;
  bool hasFormatting = false;

  @override
  void addSubdocument(Subdocument document) {
    added.add(document);
  }

  @override
  void clearFormattingCache() {
    formatCleared = true;
  }

  @override
  void deleteSharedType(SharedTypePlaceholder sharedType) {
    deletedTypes.add(sharedType);
  }

  @override
  void gcSharedType(SharedTypePlaceholder sharedType) {
    gcTypes.add(sharedType);
  }

  @override
  void integrateSharedType(SharedTypePlaceholder sharedType) {
    integratedTypes.add(sharedType);
  }

  @override
  void loadSubdocument(Subdocument document) {
    loaded.add(document);
  }

  @override
  void markDeleted(int length) {
    deletedLengths.add(length);
  }

  @override
  void markHasFormatting() {
    hasFormatting = true;
  }

  @override
  void removeSubdocument(Subdocument document) {
    removed.add(document);
  }
}

final class _PrimitiveTarget implements ContentLifecycleTarget {
  @override
  void clearFormattingCache() {}

  @override
  void markDeleted(int length) {}

  @override
  void markHasFormatting() {}
}

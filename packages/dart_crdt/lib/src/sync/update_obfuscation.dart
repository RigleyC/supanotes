/// Update obfuscation helpers for privacy-safe diagnostics.
library;

import 'dart:typed_data';

import '../binary/any_value.dart';
import '../content/content.dart';
import '../doc/doc.dart';
import '../structs/abstract_struct.dart';
import 'apply_update.dart';
import 'state_update.dart';

/// Options controlling which user-facing names remain readable.
final class UpdateObfuscationOptions {
  /// Creates obfuscation options.
  const UpdateObfuscationOptions({
    this.preserveFormattingKeys = false,
    this.preserveSubdocumentGuids = false,
    this.preserveTypeNames = false,
  });

  /// Whether formatting attribute keys should remain unchanged.
  final bool preserveFormattingKeys;

  /// Whether subdocument identifiers should remain unchanged.
  final bool preserveSubdocumentGuids;

  /// Whether nested shared type names should remain unchanged.
  final bool preserveTypeNames;
}

/// Obfuscates user content in a V1 [update] while preserving CRDT metadata.
Uint8List obfuscateUpdate(
  List<int> update, {
  UpdateObfuscationOptions options = const UpdateObfuscationOptions(),
}) {
  final doc = Doc();
  applyUpdate(doc, update);
  _obfuscateDoc(doc, options);
  return encodeStateAsUpdate(doc);
}

/// Obfuscates user content in a V2 [update] while preserving CRDT metadata.
Uint8List obfuscateUpdateV2(
  List<int> update, {
  UpdateObfuscationOptions options = const UpdateObfuscationOptions(),
}) {
  final doc = Doc();
  applyUpdateV2(doc, update);
  _obfuscateDoc(doc, options);
  return encodeStateAsUpdateV2(doc);
}

void _obfuscateDoc(Doc doc, UpdateObfuscationOptions options) {
  doc.store
    ..clearPendingStructs()
    ..clearPendingDeleteSet();
  for (final client in doc.store.clients) {
    for (final struct in doc.store.structsFor(client)) {
      if (struct is Item) {
        struct.content = _obfuscateContent(struct.content, options);
      }
    }
  }
}

AbstractContent _obfuscateContent(
  AbstractContent content,
  UpdateObfuscationOptions options,
) {
  return switch (content) {
    ContentAny(:final values) => ContentAny([
        for (var index = 0; index < values.length; index += 1)
          const JsonString('0'),
      ]),
    ContentJson(:final values) => ContentJson([
        for (var index = 0; index < values.length; index += 1)
          const JsonString('0'),
      ]),
    ContentBinary(:final bytes) => ContentBinary(
        Uint8List(bytes.length),
      ),
    ContentString(:final value) => ContentString('x' * value.length),
    ContentEmbed() => ContentEmbed('0'),
    ContentFormat(:final key) => ContentFormat(
        key: options.preserveFormattingKeys ? key : 'format',
        value: '0',
      ),
    ContentType(:final sharedType) => ContentType(
        SharedTypePlaceholder(
          kind: sharedType.kind,
          name: options.preserveTypeNames ? sharedType.name : 'type',
        ),
      ),
    ContentDocument(:final document) => ContentDocument(
        guid: options.preserveSubdocumentGuids ? document.guid : 'doc',
        collectionId: document.collectionId == null ? null : 'collection',
        meta: const JsonNull(),
        autoLoad: document.autoLoad,
        shouldLoad: document.shouldLoad,
      ),
    ContentDeleted(:final length) => ContentDeleted(length),
  };
}

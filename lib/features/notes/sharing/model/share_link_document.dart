import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';

class ShareLinkDocument {
  const ShareLinkDocument({required this.title, required this.blocks});

  final String title;
  final List<ShareLinkBlock> blocks;

  Map<String, dynamic> toSnapshot() => {
    'schemaVersion': 1,
    'blocks': blocks.map((block) => block.toJson()).toList(growable: false),
  };

  MutableDocument toMutableDocument() {
    final codec = const NoteDocumentCodec();
    return MutableDocument(
      nodes: blocks
          .map((block) => codec.decodeNode(block.toJson()))
          .toList(growable: false),
    );
  }

  factory ShareLinkDocument.fromJson(Map<String, dynamic> json) {
    final rawDocument = json['document'];
    if (rawDocument is! Map) {
      throw const FormatException('Share link response has no document');
    }
    final document = Map<String, dynamic>.from(rawDocument);
    if (document['schemaVersion'] != 1) {
      throw const FormatException(
        'Share link document has an unsupported schema version',
      );
    }
    final rawBlocks = document['blocks'];
    if (rawBlocks is! List || rawBlocks.isEmpty) {
      throw const FormatException('Share link document has no blocks');
    }
    final rawTitle = json['title'];
    if (rawTitle is! String || rawTitle.trim().isEmpty) {
      throw const FormatException('Share link response has no title');
    }
    final blockIds = <String>{};
    final blocks = rawBlocks
        .map((rawBlock) {
          if (rawBlock is! Map) {
            throw const FormatException(
              'Share link document contains an invalid block',
            );
          }
          final block = ShareLinkBlock.fromJson(
            Map<String, dynamic>.from(rawBlock),
          );
          if (!blockIds.add(block.id)) {
            throw const FormatException(
              'Share link document contains duplicate block ids',
            );
          }
          return block;
        })
        .toList(growable: false);
    return ShareLinkDocument(title: rawTitle, blocks: blocks);
  }
}

class ShareLinkBlock {
  const ShareLinkBlock({
    required this.id,
    required this.type,
    required this.delta,
    required this.metadata,
  });

  final String id;
  final String type;
  final List<Map<String, dynamic>> delta;
  final Map<String, dynamic> metadata;

  static const _supportedTypes = {
    'paragraph',
    'header1',
    'header2',
    'header3',
    'quote',
    'bulletList',
    'orderedList',
    'task',
    'divider',
    'attachment',
    'rich_link',
  };

  String get text =>
      delta.map((operation) => operation['insert']).whereType<String>().join();

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'delta': delta,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };

  factory ShareLinkBlock.fromJson(Map<String, dynamic> json) {
    final rawDelta = json['delta'];
    final rawId = json['id'];
    final rawType = json['type'];
    if (rawId is! String || rawId.isEmpty) {
      throw const FormatException('Share link block has no id');
    }
    if (rawType is! String || rawType.isEmpty) {
      throw const FormatException('Share link block has no type');
    }
    if (!_supportedTypes.contains(rawType)) {
      throw FormatException('Unsupported share link block type: $rawType');
    }
    if (rawDelta is! List) {
      throw const FormatException('Share link block has no delta');
    }
    final delta = rawDelta
        .map((rawOperation) {
          if (rawOperation is! Map) {
            throw const FormatException(
              'Share link block contains an invalid delta',
            );
          }
          final operation = Map<String, dynamic>.from(rawOperation);
          if (operation['insert'] is! String) {
            throw const FormatException(
              'Share link block contains a non-text delta operation',
            );
          }
          if (operation['attributes'] != null &&
              operation['attributes'] is! Map) {
            throw const FormatException(
              'Share link block contains invalid delta attributes',
            );
          }
          final attributes = operation['attributes'];
          if (attributes is Map) {
            for (final entry in attributes.entries) {
              if (entry.key is! String) {
                throw const FormatException(
                  'Share link block contains invalid delta attribute names',
                );
              }
              if (entry.key == 'link') {
                final uri = entry.value is String
                    ? Uri.tryParse(entry.value as String)
                    : null;
                if (uri == null) {
                  throw const FormatException(
                    'Share link block contains an invalid link attribute',
                  );
                }
              } else if (entry.key.toString().startsWith('link:') &&
                  entry.value == true &&
                  Uri.tryParse(entry.key.toString().substring(5)) == null) {
                throw const FormatException(
                  'Share link block contains an invalid link attribution',
                );
              }
            }
          }
          return operation;
        })
        .toList(growable: false);
    final rawMetadata = json['metadata'];
    if (rawMetadata != null && rawMetadata is! Map) {
      throw const FormatException('Share link block has invalid metadata');
    }
    final metadata = rawMetadata == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(rawMetadata);
    _validateMetadata(rawType, metadata);
    return ShareLinkBlock(
      id: rawId,
      type: rawType,
      delta: delta,
      metadata: metadata,
    );
  }

  static void _validateMetadata(String type, Map<String, dynamic> metadata) {
    void requireType(String key, bool condition) {
      if (metadata[key] != null && !condition) {
        throw FormatException('Invalid $key metadata for $type block');
      }
    }

    switch (type) {
      case 'rich_link':
        for (final key in const [
          'url',
          'title',
          'description',
          'imageUrl',
          'domain',
        ]) {
          requireType(key, metadata[key] is String);
        }
      case 'task':
        requireType('isCompleted', metadata['isCompleted'] is bool);
        requireType('checked', metadata['checked'] is bool);
        requireType('indent', metadata['indent'] is int);
        for (final key in const [
          'dueDate',
          'recurrenceRule',
          'recurrence',
          'reminder',
        ]) {
          requireType(key, metadata[key] is String);
        }
        requireType('hasTime', metadata['hasTime'] is bool);
      case 'bulletList' || 'orderedList':
        requireType('indent', metadata['indent'] is int);
      case 'attachment':
        for (final key in const [
          'attachmentId',
          'filename',
          'mimeType',
          'url',
        ]) {
          requireType(key, metadata[key] is String);
        }
        requireType('fileSize', metadata['fileSize'] is int);
    }
  }
}

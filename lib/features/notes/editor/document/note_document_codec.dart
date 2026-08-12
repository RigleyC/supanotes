import 'dart:collection';

import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:super_editor/super_editor.dart';

import 'attachment_nodes.dart';
import 'note_document_constants.dart';

typedef _EncodedNode = ({
  String type,
  AttributedText text,
  Map<String, dynamic> metadata,
});

/// Strict, transport-independent representation of a canonical note
/// snapshot. Sharing and sync envelopes may carry this value, but only this
/// document layer validates and decodes its block contract.
dynamic _freezeJsonValue(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable({
      for (final entry in value.entries)
        entry.key.toString(): _freezeJsonValue(entry.value),
    });
  }
  if (value is List) {
    return UnmodifiableListView<dynamic>(value.map(_freezeJsonValue));
  }
  return value;
}

final class NoteDocumentSnapshot {
  NoteDocumentSnapshot._(List<NoteDocumentBlock> blocks)
    : blocks = UnmodifiableListView<NoteDocumentBlock>(blocks);

  factory NoteDocumentSnapshot.fromJson(Map<String, dynamic> json) =>
      const NoteDocumentCodec().parseSnapshot(json);

  final List<NoteDocumentBlock> blocks;

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'blocks': blocks.map((block) => block.toJson()).toList(growable: false),
  };

  MutableDocument toMutableDocument() =>
      const NoteDocumentCodec().decodeSnapshot(this);
}

final class NoteDocumentBlock {
  NoteDocumentBlock({
    required this.id,
    required this.type,
    required List<Map<String, dynamic>> delta,
    required Map<String, dynamic> metadata,
  }) : delta = UnmodifiableListView<Map<String, dynamic>>(
         delta.map(
           (operation) => _freezeJsonValue(operation) as Map<String, dynamic>,
         ),
       ),
       metadata = _freezeJsonValue(metadata) as Map<String, dynamic>;

  final String id;
  final String type;
  final List<Map<String, dynamic>> delta;
  final Map<String, dynamic> metadata;

  String get text =>
      delta.map((operation) => operation['insert']).whereType<String>().join();

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'delta': delta,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

class NoteDocumentCodec {
  const NoteDocumentCodec();

  static const supportedBlockTypes = {
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

  NoteDocumentSnapshot parseSnapshot(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException(
        'Note document has an unsupported schema version',
      );
    }
    final rawBlocks = json['blocks'];
    if (rawBlocks is! List || rawBlocks.isEmpty) {
      throw const FormatException('Note document has no blocks');
    }

    final ids = <String>{};
    final blocks = rawBlocks
        .map((rawBlock) {
          if (rawBlock is! Map) {
            throw const FormatException(
              'Note document contains an invalid block',
            );
          }
          final block = _parseBlock(Map<String, dynamic>.from(rawBlock));
          if (!ids.add(block.id)) {
            throw const FormatException(
              'Note document contains duplicate block ids',
            );
          }
          return block;
        })
        .toList(growable: false);
    return NoteDocumentSnapshot._(blocks);
  }

  MutableDocument decodeSnapshot(NoteDocumentSnapshot snapshot) {
    return MutableDocument(
      nodes: snapshot.blocks.map(_decodeSnapshotBlock).toList(growable: false),
    );
  }

  DocumentNode _decodeSnapshotBlock(NoteDocumentBlock block) {
    final metadata = Map<String, dynamic>.from(block.metadata);
    var type = block.type;
    if (type == 'paragraph') {
      final rawBlockType = metadata['blockType'];
      final blockType = rawBlockType is Attribution
          ? rawBlockType
          : (rawBlockType is String ? attributionFromName(rawBlockType) : null);
      if (blockType != null) {
        type = blockType.id == blockquoteAttribution.id
            ? 'quote'
            : blockType.id;
        metadata['blockType'] = blockType;
      } else {
        metadata.remove('blockType');
      }
    }

    return createNodeFromBlockType(
      nodeId: block.id,
      type: type,
      text: attributedFromDelta(block.delta),
      isTaskComplete: metadata['isCompleted'] as bool? ?? false,
      metadata: metadata,
    );
  }

  NoteDocumentBlock _parseBlock(
    Map<String, dynamic> json, {
    bool allowEmptyDeltaOperations = false,
    bool allowMutationDeltaOperations = false,
  }) {
    final rawId = json['id'];
    final rawType = json['type'];
    _validateBlockIdentity(rawId, rawType);

    final delta = _parseDelta(
      json['delta'],
      allowEmptyDeltaOperations: allowEmptyDeltaOperations,
      allowMutationDeltaOperations: allowMutationDeltaOperations,
    );
    final metadata = _parseMetadata(json['metadata']);
    _validateMetadata(rawType as String, metadata);
    return NoteDocumentBlock(
      id: rawId as String,
      type: rawType,
      delta: delta,
      metadata: metadata,
    );
  }

  void _validateBlockIdentity(dynamic rawId, dynamic rawType) {
    if (rawId is! String || rawId.isEmpty) {
      throw const FormatException('Note document block has no id');
    }
    if (rawType is! String || rawType.isEmpty) {
      throw const FormatException('Note document block has no type');
    }
    if (!supportedBlockTypes.contains(rawType)) {
      throw FormatException('Unsupported note document block type: $rawType');
    }
  }

  List<Map<String, dynamic>> _parseDelta(
    dynamic rawDelta, {
    required bool allowEmptyDeltaOperations,
    required bool allowMutationDeltaOperations,
  }) {
    if (rawDelta is! List) {
      throw const FormatException('Note document block has no delta');
    }
    return rawDelta
        .map<Map<String, dynamic>?>((rawOperation) {
          return _parseDeltaOperation(
            rawOperation,
            allowEmptyDeltaOperations: allowEmptyDeltaOperations,
            allowMutationDeltaOperations: allowMutationDeltaOperations,
          );
        })
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  Map<String, dynamic>? _parseDeltaOperation(
    dynamic rawOperation, {
    required bool allowEmptyDeltaOperations,
    required bool allowMutationDeltaOperations,
  }) {
    if (rawOperation is! Map) {
      throw const FormatException(
        'Note document block contains an invalid delta',
      );
    }
    final operation = Map<String, dynamic>.from(rawOperation);
    if (allowEmptyDeltaOperations && operation.isEmpty) {
      return <String, dynamic>{'insert': ''};
    }
    if (operation['insert'] is! String) {
      if (allowMutationDeltaOperations && _isMutationOperation(operation)) {
        return null;
      }
      throw const FormatException(
        'Note document block contains a non-text delta operation',
      );
    }
    _validateDeltaAttributes(operation['attributes']);
    return operation;
  }

  bool _isMutationOperation(Map<String, dynamic> operation) {
    return !operation.containsKey('insert') &&
        (operation['delete'] is int || operation['retain'] is int);
  }

  void _validateDeltaAttributes(dynamic rawAttributes) {
    if (rawAttributes != null && rawAttributes is! Map) {
      throw const FormatException(
        'Note document block contains invalid delta attributes',
      );
    }
    if (rawAttributes is! Map) return;

    for (final entry in rawAttributes.entries) {
      if (entry.key is! String) {
        throw const FormatException(
          'Note document block contains invalid delta attribute names',
        );
      }
      if (entry.key == 'link') {
        final uri = entry.value is String
            ? Uri.tryParse(entry.value as String)
            : null;
        if (uri == null) {
          throw const FormatException(
            'Note document block contains an invalid link attribute',
          );
        }
      } else if (entry.key.toString().startsWith('link:')) {
        if (entry.value != true ||
            Uri.tryParse(entry.key.toString().substring(5)) == null) {
          throw const FormatException(
            'Note document block contains an invalid link attribution',
          );
        }
      }
    }
  }

  Map<String, dynamic> _parseMetadata(dynamic rawMetadata) {
    if (rawMetadata != null && rawMetadata is! Map) {
      throw const FormatException('Note document block has invalid metadata');
    }
    return rawMetadata == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(rawMetadata);
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

  bool isEmptyDocumentPlaceholder(MutableDocument document) {
    if (document.nodeCount != 1) return false;
    final node = document.first;
    return node is TextNode &&
        node.id == initialNoteBlockId &&
        node.text.toPlainText().isEmpty;
  }

  // ---------------------------------------------------------------------------
  // Attribution helpers
  // ---------------------------------------------------------------------------

  static String attributionToName(Attribution attribution) {
    if (attribution == boldAttribution) return 'bold';
    if (attribution == italicsAttribution) return 'italics';
    if (attribution == strikethroughAttribution) return 'strikethrough';
    if (attribution == underlineAttribution) return 'underline';
    if (attribution is LinkAttribution) {
      return 'link:${attribution.plainTextUri.toString()}';
    }
    return attribution.id;
  }

  static Attribution attributionFromNameStatic(String name) {
    if (name == 'bold') return boldAttribution;
    if (name == 'italics') return italicsAttribution;
    if (name == 'strikethrough') return strikethroughAttribution;
    if (name == 'underline') return underlineAttribution;
    if (name.startsWith('link:')) {
      final uri = Uri.tryParse(name.substring(5));
      return uri == null
          ? NamedAttribution(name)
          : LinkAttribution.fromUri(uri);
    }
    return NamedAttribution(name);
  }

  static AttributedText deserializeAttributedText(Map<String, dynamic> data) {
    final text = data['text'] as String? ?? '';
    final spansData = data['spans'] as List<dynamic>? ?? [];
    final spans = AttributedSpans();

    for (final s in spansData) {
      final spanMap = s as Map<String, dynamic>;
      final attributionName = spanMap['attribution'] as String?;
      final start = spanMap['start'] as int?;
      final storedEnd = spanMap['end'] as int?;

      if (attributionName == null ||
          start == null ||
          storedEnd == null ||
          storedEnd == -1) {
        continue;
      }

      final end = data['spansVersion'] == 2 ? storedEnd : storedEnd + 1;
      final safeStart = start.clamp(0, text.length);
      final safeEnd = end.clamp(safeStart, text.length);
      if (safeEnd > safeStart) {
        spans.addAttribution(
          newAttribution: attributionFromNameStatic(attributionName),
          start: safeStart,
          end: safeEnd - 1,
        );
      }
    }

    return AttributedText(text, spans);
  }

  // ---------------------------------------------------------------------------
  // Instance Methods (OT document conversion & Delta operations)
  // ---------------------------------------------------------------------------

  dynamic _toJsonValue(dynamic value) {
    if (value is Attribution) return value.id;
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Map) {
      return value.map(
        (key, entry) => MapEntry(key.toString(), _toJsonValue(entry)),
      );
    }
    if (value is Iterable) return value.map(_toJsonValue).toList();
    return value;
  }

  Map<String, dynamic> encodeNode(DocumentNode node) {
    final encoded = _encodeNode(node);

    final deltaOps = encodeAttributedTextToDelta(encoded.text);

    final result = <String, dynamic>{
      'id': node.id,
      'type': encoded.type,
      'delta': deltaOps,
    };
    if (encoded.metadata.isNotEmpty) {
      result['metadata'] = _toJsonValue(encoded.metadata);
    }
    return result;
  }

  _EncodedNode _encodeNode(DocumentNode node) => switch (node) {
    TaskNode node => _encodeTaskNode(node),
    HorizontalRuleNode node => _encodeHorizontalRuleNode(node),
    ListItemNode node => _encodeListItemNode(node),
    ParagraphNode node => _encodeParagraphNode(node),
    DocumentAttachmentNode node => _encodeAttachmentNode(node),
    RichLinkNode node => _encodeRichLinkNode(node),
    ImageNode node => _encodeImageNode(node),
    _ => _encodeTextNode(node),
  };

  _EncodedNode _encodeTaskNode(TaskNode node) {
    final metadata = <String, dynamic>{'isCompleted': node.isComplete};
    if (node.indent != 0) {
      metadata['indent'] = node.indent;
    }
    for (final entry in node.metadata.entries) {
      if (entry.key != 'isCompleted') {
        metadata[entry.key] = entry.value;
      }
    }
    return (type: 'task', text: node.text, metadata: metadata);
  }

  _EncodedNode _encodeHorizontalRuleNode(HorizontalRuleNode node) => (
    type: 'divider',
    text: AttributedText(),
    metadata: Map<String, dynamic>.from(node.metadata),
  );

  _EncodedNode _encodeListItemNode(ListItemNode node) {
    final metadata = <String, dynamic>{};
    if (node.indent != 0) {
      metadata['indent'] = node.indent;
    }
    for (final entry in node.metadata.entries) {
      if (entry.key != 'blockType') {
        metadata[entry.key] = entry.value;
      }
    }
    return (
      type: node.type == ListItemType.ordered ? 'orderedList' : 'bulletList',
      text: node.text,
      metadata: metadata,
    );
  }

  _EncodedNode _encodeParagraphNode(ParagraphNode node) {
    final blockType = node.metadata['blockType'];
    final type = switch (blockType) {
      header1Attribution => 'header1',
      header2Attribution => 'header2',
      header3Attribution => 'header3',
      blockquoteAttribution => 'quote',
      _ => 'paragraph',
    };
    final metadata = <String, dynamic>{};
    for (final entry in node.metadata.entries) {
      if (entry.key != 'blockType') {
        metadata[entry.key] = entry.value;
      }
    }
    return (type: type, text: node.text, metadata: metadata);
  }

  _EncodedNode _encodeAttachmentNode(DocumentAttachmentNode node) {
    final metadata = <String, dynamic>{
      'attachmentId': node.metadata['attachmentId'] ?? node.id,
      'filename': node.metadata['filename'] ?? 'attachment',
      'fileSize': node.metadata['fileSize'] ?? 0,
      'mimeType': node.metadata['mimeType'] ?? 'application/octet-stream',
    };
    if (node.metadata['url'] != null) metadata['url'] = node.metadata['url'];
    return (type: 'attachment', text: AttributedText(), metadata: metadata);
  }

  _EncodedNode _encodeRichLinkNode(RichLinkNode node) {
    final metadata = <String, dynamic>{};
    if (node.url != null) metadata['url'] = node.url;
    if (node.title != null) metadata['title'] = node.title;
    if (node.description != null) metadata['description'] = node.description;
    if (node.imageUrl != null) metadata['imageUrl'] = node.imageUrl;
    if (node.domain != null) metadata['domain'] = node.domain;
    return (type: 'rich_link', text: AttributedText(), metadata: metadata);
  }

  _EncodedNode _encodeImageNode(ImageNode node) {
    final metadata = <String, dynamic>{'url': node.imageUrl};
    if (node.altText.isNotEmpty) metadata['filename'] = node.altText;
    return (type: 'attachment', text: AttributedText(), metadata: metadata);
  }

  _EncodedNode _encodeTextNode(DocumentNode node) => (
    type: 'paragraph',
    text: node is TextNode ? node.text : AttributedText(),
    metadata: <String, dynamic>{},
  );

  List<Map<String, dynamic>> encodeAttributedTextToDelta(AttributedText text) {
    return _deltaFromAttributedText(text).toJson();
  }

  Delta _deltaFromAttributedText(AttributedText text) {
    final plainText = text.toPlainText();
    final delta = Delta();
    if (plainText.isEmpty) return delta;

    for (final span in text.computeAttributionSpans()) {
      final start = span.start;
      final end = span.end + 1;
      if (start >= end || start >= plainText.length) continue;

      final attributes = <String, dynamic>{};
      for (final attribution in span.attributions) {
        final id = attributionToName(attribution);
        if (id != 'composing') {
          attributes[id] = true;
        }
      }

      delta.insert(
        plainText.substring(
          start,
          end > plainText.length ? plainText.length : end,
        ),
        attributes.isEmpty ? null : attributes,
      );
    }
    return delta;
  }

  DocumentNode decodeNode(Map<String, dynamic> blockData) {
    return _decodeNode(blockData, allowMutationDeltaOperations: false);
  }

  /// Decodes a local persisted block and removes OT mutation operations that
  /// can be present in a malformed cached snapshot. They are not document
  /// content; the strict transport decoder remains unchanged.
  DocumentNode decodePersistedNode(Map<String, dynamic> blockData) {
    return _decodeNode(blockData, allowMutationDeltaOperations: true);
  }

  DocumentNode _decodeNode(
    Map<String, dynamic> blockData, {
    required bool allowMutationDeltaOperations,
  }) {
    final normalized = Map<String, dynamic>.from(blockData);
    normalized['id'] ??= Editor.createNodeId();
    if (normalized['delta'] == null && normalized['content'] is List) {
      normalized['delta'] = normalized['content'];
    }
    return _decodeSnapshotBlock(
      _parseBlock(
        normalized,
        allowEmptyDeltaOperations: true,
        allowMutationDeltaOperations: allowMutationDeltaOperations,
      ),
    );
  }

  List<Map<String, dynamic>> encodeDocument(MutableDocument document) {
    final blocks = <Map<String, dynamic>>[];
    for (var i = 0; i < document.nodeCount; i++) {
      final node = document.getNodeAt(i);
      if (node != null) {
        blocks.add(encodeNode(node));
      }
    }
    return blocks;
  }

  DocumentNode createNodeFromBlockType({
    required String nodeId,
    required String type,
    required AttributedText text,
    bool isTaskComplete = false,
    ListItemType itemType = ListItemType.unordered,
    Map<String, dynamic>? metadata,
  }) {
    Map<String, dynamic> paragraphMetadata(Attribution? blockType) {
      final normalized = Map<String, dynamic>.from(metadata ?? {});
      normalized.remove('blockType');
      if (blockType != null) {
        normalized['blockType'] = blockType;
      }
      return normalized;
    }

    if (type == 'divider') {
      return HorizontalRuleNode(id: nodeId, metadata: metadata ?? {});
    }
    if (type == 'attachment') {
      return DocumentAttachmentNode(id: nodeId, metadata: metadata ?? {});
    }
    if (type == 'rich_link') {
      final richLinkMetadata = metadata ?? const <String, dynamic>{};
      return RichLinkNode(
        id: nodeId,
        url: richLinkMetadata['url'] as String?,
        title: richLinkMetadata['title'] as String?,
        description: richLinkMetadata['description'] as String?,
        imageUrl: richLinkMetadata['imageUrl'] as String?,
        domain: richLinkMetadata['domain'] as String?,
        metadata: richLinkMetadata,
      );
    }
    if (type == 'bulletList') {
      return ListItemNode(
        id: nodeId,
        itemType: ListItemType.unordered,
        text: text,
        indent: metadata?['indent'] as int? ?? 0,
        metadata: metadata ?? {},
      );
    }
    if (type == 'orderedList') {
      return ListItemNode(
        id: nodeId,
        itemType: ListItemType.ordered,
        text: text,
        indent: metadata?['indent'] as int? ?? 0,
        metadata: metadata ?? {},
      );
    }
    if (type == 'task') {
      return TaskNode(
        id: nodeId,
        text: text,
        isComplete: isTaskComplete,
        indent: metadata?['indent'] as int? ?? 0,
        metadata: metadata ?? {},
      );
    }
    if (type == 'header1') {
      return ParagraphNode(
        id: nodeId,
        text: text,
        metadata: paragraphMetadata(header1Attribution),
      );
    }
    if (type == 'header2') {
      return ParagraphNode(
        id: nodeId,
        text: text,
        metadata: paragraphMetadata(header2Attribution),
      );
    }
    if (type == 'header3') {
      return ParagraphNode(
        id: nodeId,
        text: text,
        metadata: paragraphMetadata(header3Attribution),
      );
    }
    if (type == 'quote') {
      return ParagraphNode(
        id: nodeId,
        text: text,
        metadata: paragraphMetadata(blockquoteAttribution),
      );
    }
    final blockTypeAttr = attributionFromName(type);
    final ParagraphNode paragraph = ParagraphNode(
      id: nodeId,
      text: text,
      metadata: paragraphMetadata(blockTypeAttr),
    );
    return paragraph;
  }

  AttributedText attributedFromDelta(List<dynamic>? delta) {
    if (delta == null || delta.isEmpty) return AttributedText();

    final documentOperations = delta
        .where((operation) => operation is! Map || operation.isNotEmpty)
        .toList(growable: false);
    if (documentOperations.isEmpty) return AttributedText();

    return _attributedTextFromDelta(Delta.fromJson(documentOperations));
  }

  AttributedText _attributedTextFromDelta(Delta documentDelta) {
    final span = AttributedSpans();
    final buffer = StringBuffer();
    for (final op in documentDelta.operations) {
      _appendOperation(op, buffer, span);
    }
    return AttributedText(buffer.toString(), span);
  }

  void _appendOperation(
    Operation operation,
    StringBuffer buffer,
    AttributedSpans span,
  ) {
    final insert = operation.data;
    if (!operation.isInsert || insert is! String || insert.isEmpty) return;

    final start = buffer.length;
    buffer.write(insert);
    _appendAttributions(
      operation.attributes,
      span: span,
      start: start,
      end: buffer.length - 1,
    );
  }

  void _appendAttributions(
    Map<String, dynamic>? attributes, {
    required AttributedSpans span,
    required int start,
    required int end,
  }) {
    if (attributes == null) return;

    for (final entry in attributes.entries) {
      final attribution = _attributionFromDeltaEntry(entry);
      if (attribution == null) continue;
      span.addAttribution(newAttribution: attribution, start: start, end: end);
    }
  }

  Attribution? _attributionFromDeltaEntry(MapEntry<String, dynamic> entry) {
    if (entry.key == 'link' && entry.value is String) {
      final uri = Uri.tryParse(entry.value as String);
      return uri == null ? null : LinkAttribution.fromUri(uri);
    }
    if (entry.value == true) return attributionFromId(entry.key);
    return null;
  }

  AttributedText? applyDeltaToText(
    AttributedText source,
    List<Map<String, dynamic>> ops,
  ) {
    if (ops.any((operation) => !_isValidTextChangeOperation(operation))) {
      return null;
    }

    final sourceDelta = _deltaFromAttributedText(source);
    final changeDelta = Delta.fromJson(ops);
    var consumedSourceLength = 0;

    for (final operation in changeDelta.operations) {
      if (operation.length == null || operation.length! < 0) return null;
      if (operation.isInsert && operation.data is! String) return null;
      if (operation.isRetain || operation.isDelete) {
        consumedSourceLength += operation.length!;
        if (consumedSourceLength > source.toPlainText().length) {
          return null;
        }
      }
    }

    final resultDelta = sourceDelta.compose(changeDelta);
    return _attributedTextFromDelta(resultDelta);
  }

  bool _isValidTextChangeOperation(Map<String, dynamic> operation) {
    final operationKeys = const {
      'insert',
      'retain',
      'delete',
    }.where(operation.containsKey).toList(growable: false);
    if (operationKeys.length != 1) return false;

    final value = operation[operationKeys.single];
    if (operationKeys.single == 'insert') {
      if (value is! String) return false;
    } else if (value is! int || value < 0) {
      return false;
    }

    final attributes = operation['attributes'];
    return attributes == null || attributes is Map;
  }

  String? blockTypeName(DocumentNode node) {
    if (node is ParagraphNode) {
      return _paragraphBlockTypeName(node);
    }
    if (node is ListItemNode) {
      return node.type == ListItemType.ordered ? 'orderedList' : 'bulletList';
    }
    if (node is TaskNode) return 'task';
    if (node is HorizontalRuleNode) return 'divider';
    if (node is DocumentAttachmentNode) return 'attachment';
    if (node is RichLinkNode) return 'rich_link';
    return null;
  }

  String _paragraphBlockTypeName(ParagraphNode node) {
    final raw = node.getMetadataValue('blockType');
    final blockType = raw is Attribution
        ? raw
        : (raw is String ? attributionFromName(raw) : null);
    if (blockType == header1Attribution || raw == 'header1') return 'header1';
    if (blockType == header2Attribution || raw == 'header2') return 'header2';
    if (blockType == header3Attribution || raw == 'header3') return 'header3';
    if (blockType == blockquoteAttribution || raw == 'quote') return 'quote';
    return 'paragraph';
  }

  Attribution? attributionFromId(String id) {
    if (id == 'bold') return boldAttribution;
    if (id == 'italics') return italicsAttribution;
    if (id == 'strikethrough') return strikethroughAttribution;
    if (id == 'underline') return underlineAttribution;
    if (id.startsWith('link:')) {
      final uri = Uri.tryParse(id.substring('link:'.length));
      return uri == null ? null : LinkAttribution.fromUri(uri);
    }
    return null;
  }

  Attribution? attributionFromName(String? name) {
    if (name == null) return null;
    if (name == 'header1') return header1Attribution;
    if (name == 'header2') return header2Attribution;
    if (name == 'header3') return header3Attribution;
    if (name == 'quote') return blockquoteAttribution;
    return null;
  }
}

import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:super_editor/super_editor.dart';

import 'attachment_nodes.dart';
import 'note_document_constants.dart';

class NoteDocumentCodec {
  const NoteDocumentCodec();

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
      return LinkAttribution.fromUri(Uri.parse(name.substring(5)));
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
    final String blockId = node.id;
    String type = 'paragraph';
    final Map<String, dynamic> metadata = {};
    AttributedText text = AttributedText();

    if (node is TaskNode) {
      type = 'task';
      text = node.text;
      metadata['isCompleted'] = node.isComplete;
      if (node.indent != 0) {
        metadata['indent'] = node.indent;
      }
      for (final entry in node.metadata.entries) {
        if (entry.key != 'isCompleted') {
          metadata[entry.key] = entry.value;
        }
      }
    } else if (node is HorizontalRuleNode) {
      type = 'divider';
      for (final entry in node.metadata.entries) {
        metadata[entry.key] = entry.value;
      }
    } else if (node is ListItemNode) {
      type = node.type == ListItemType.ordered ? 'orderedList' : 'bulletList';
      text = node.text;
      if (node.indent != 0) {
        metadata['indent'] = node.indent;
      }
      for (final entry in node.metadata.entries) {
        if (entry.key != 'blockType') {
          metadata[entry.key] = entry.value;
        }
      }
    } else if (node is ParagraphNode) {
      text = node.text;
      final blockType = node.metadata['blockType'];
      if (blockType == header1Attribution) {
        type = 'header1';
      } else if (blockType == header2Attribution) {
        type = 'header2';
      } else if (blockType == header3Attribution) {
        type = 'header3';
      } else if (blockType == blockquoteAttribution) {
        type = 'quote';
      }
      for (final entry in node.metadata.entries) {
        if (entry.key != 'blockType') {
          metadata[entry.key] = entry.value;
        }
      }
    } else if (node is DocumentAttachmentNode) {
      type = 'attachment';
      metadata['attachmentId'] = node.metadata['attachmentId'] ?? node.id;
      metadata['filename'] = node.metadata['filename'] ?? 'attachment';
      metadata['fileSize'] = node.metadata['fileSize'] ?? 0;
      metadata['mimeType'] =
          node.metadata['mimeType'] ?? 'application/octet-stream';
      if (node.metadata['url'] != null) metadata['url'] = node.metadata['url'];
    } else if (node is RichLinkNode) {
      type = 'rich_link';
      if (node.url != null) metadata['url'] = node.url;
      if (node.title != null) metadata['title'] = node.title;
      if (node.description != null) metadata['description'] = node.description;
      if (node.imageUrl != null) metadata['imageUrl'] = node.imageUrl;
    } else if (node is ImageNode) {
      type = 'attachment';
      metadata['url'] = node.imageUrl;
      if (node.altText.isNotEmpty) metadata['filename'] = node.altText;
    } else if (node is TextNode) {
      text = node.text;
    }

    final deltaOps = encodeAttributedTextToDelta(text);

    final result = <String, dynamic>{
      'id': blockId,
      'type': type,
      'delta': deltaOps,
    };
    if (metadata.isNotEmpty) {
      result['metadata'] = _toJsonValue(metadata);
    }
    return result;
  }

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
    final String nodeId = blockData['id'] as String? ?? Editor.createNodeId();
    String type = blockData['type'] as String? ?? 'paragraph';
    final List<dynamic>? content =
        (blockData['content'] ?? blockData['delta']) as List<dynamic>?;
    final Map<String, dynamic> metadata = Map<String, dynamic>.from(
      blockData['metadata'] as Map? ?? {},
    );
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

    final AttributedText text = (content != null && content.isNotEmpty)
        ? attributedFromDelta(content)
        : deserializeAttributedText(blockData);
    final bool isTaskComplete = metadata['isCompleted'] as bool? ?? false;

    final node = createNodeFromBlockType(
      nodeId: nodeId,
      type: type,
      text: text,
      isTaskComplete: isTaskComplete,
      metadata: metadata,
    );
    return node;
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
    final buf = StringBuffer();
    for (final op in documentDelta.operations) {
      if (!op.isInsert || op.data is! String || (op.data as String).isEmpty) {
        continue;
      }

      final insert = op.data as String;
      final start = buf.length;
      buf.write(insert);
      final attrs = op.attributes;
      if (attrs != null) {
        for (final entry in attrs.entries) {
          if (entry.value == true) {
            final attr = attributionFromId(entry.key);
            if (attr != null) {
              span.addAttribution(
                newAttribution: attr,
                start: start,
                end: buf.length - 1,
              );
            }
          }
        }
      }
    }
    return AttributedText(buf.toString(), span);
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
    if (node is ListItemNode) {
      return node.type == ListItemType.ordered ? 'orderedList' : 'bulletList';
    }
    if (node is TaskNode) return 'task';
    if (node is HorizontalRuleNode) return 'divider';
    if (node is DocumentAttachmentNode) return 'attachment';
    if (node is RichLinkNode) return 'rich_link';
    return null;
  }

  Attribution? attributionFromId(String id) {
    if (id == 'bold') return boldAttribution;
    if (id == 'italics') return italicsAttribution;
    if (id == 'strikethrough') return strikethroughAttribution;
    if (id == 'underline') return underlineAttribution;
    if (id.startsWith('link:')) {
      return LinkAttribution.fromUri(Uri.parse(id.substring('link:'.length)));
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

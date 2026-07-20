import 'package:super_editor/super_editor.dart';

import 'attachment_nodes.dart';
import 'note_node.dart';
import 'yjs_task_entry.dart';

const header4Attribution = NamedAttribution('header4');
const header5Attribution = NamedAttribution('header5');
const header6Attribution = NamedAttribution('header6');
const corruptedAttribution = NamedAttribution('corrupted');

class NodeCodec {
  NodeCodec._();

  static String _attributionToName(Attribution attribution) {
    if (attribution == boldAttribution) return 'bold';
    if (attribution == italicsAttribution) return 'italics';
    if (attribution == strikethroughAttribution) return 'strikethrough';
    if (attribution == underlineAttribution) return 'underline';
    if (attribution is LinkAttribution) {
      return 'link:${attribution.plainTextUri.toString()}';
    }
    return attribution.id;
  }

  static Attribution _attributionFromName(String name) {
    if (name == 'bold') return boldAttribution;
    if (name == 'italics') return italicsAttribution;
    if (name == 'strikethrough') return strikethroughAttribution;
    if (name == 'underline') return underlineAttribution;
    if (name.startsWith('link:')) {
      return LinkAttribution.fromUri(Uri.parse(name.substring(5)));
    }
    return NamedAttribution(name);
  }

  static Map<String, dynamic> _serializeAttributedText(AttributedText text) {
    final spansList = <Map<String, dynamic>>[];
    for (final span in text.spans.markers) {
      if (span.isStart) {
        if (span.attribution.id == 'composing') continue;
        spansList.add({
          'attribution': _attributionToName(span.attribution),
          'start': span.offset,
          'end': -1,
        });
      } else {
        if (span.attribution.id == 'composing') continue;
        final name = _attributionToName(span.attribution);
        for (int i = spansList.length - 1; i >= 0; i--) {
          if (spansList[i]['attribution'] == name &&
              spansList[i]['end'] == -1) {
            // SuperEditor end markers are inclusive, while persisted spans use
            // an exclusive end offset so they remain valid at text.length.
            spansList[i]['end'] = span.offset + 1;
            break;
          }
        }
      }
    }
    return {'text': text.toPlainText(), 'spans': spansList, 'spansVersion': 2};
  }

  static Map<String, dynamic> nodeData(DocumentNode node) {
    if (node is TaskNode) {
      return {..._serializeAttributedText(node.text), 'indent': node.indent};
    }
    if (node is ParagraphNode) {
      final blockType = node.metadata['blockType'];
      if (blockType == header1Attribution ||
          blockType == header2Attribution ||
          blockType == header3Attribution ||
          blockType == header4Attribution ||
          blockType == header5Attribution ||
          blockType == header6Attribution) {
        int level = 1;
        if (blockType == header2Attribution) level = 2;
        if (blockType == header3Attribution) level = 3;
        if (blockType == header4Attribution) level = 4;
        if (blockType == header5Attribution) level = 5;
        if (blockType == header6Attribution) level = 6;
        return {..._serializeAttributedText(node.text), 'level': level};
      }
      if (blockType == blockquoteAttribution) {
        return {..._serializeAttributedText(node.text)};
      }
      return {..._serializeAttributedText(node.text)};
    }
    if (node is ListItemNode) {
      return {
        ..._serializeAttributedText(node.text),
        'type': node.type == ListItemType.ordered ? 'ordered' : 'unordered',
        'indent': node.indent,
      };
    }
    if (node is TextNode) {
      return {..._serializeAttributedText(node.text)};
    }
    if (node is ImageNode) {
      return {'url': node.imageUrl, 'alt': node.altText};
    }
    if (node is HorizontalRuleNode) {
      return <String, dynamic>{};
    }
    if (node is DocumentAttachmentNode) {
      return {'id': node.id};
    }
    if (node is RichLinkNode) {
      return {
        'id': node.id,
        if (node.url != null) 'url': node.url,
        if (node.title != null) 'title': node.title,
        if (node.description != null) 'description': node.description,
        if (node.imageUrl != null) 'image_url': node.imageUrl,
        if (node.domain != null) 'domain': node.domain,
      };
    }
    return <String, dynamic>{};
  }

  static MutableDocument documentFromNodes(List<NoteNode> nodes) {
    final documentNodes = <DocumentNode>[];
    for (final node in nodes) {
      final docNode = _nodeFromData(node);
      if (docNode != null) {
        documentNodes.add(docNode);
      }
    }
    if (documentNodes.isEmpty) {
      return MutableDocument(
        nodes: [
          ParagraphNode(id: Editor.createNodeId(), text: AttributedText()),
        ],
      );
    }
    return MutableDocument(nodes: documentNodes);
  }

  static DocumentNode createNodeFromSchema(NoteNode schema) {
    return _createNode(id: schema.id, type: schema.type, data: schema.data);
  }

  static DocumentNode _createNode({
    required String id,
    required String type,
    required Map<String, dynamic> data,
  }) {
    final attributedText = _deserializeAttributedText(data);

    if (type == 'task') {
      return TaskNode(
        id: id,
        text: attributedText,
        isComplete: data['completed'] as bool? ?? false,
        indent: data['indent'] as int? ?? 0,
      );
    }
    if (type == 'list_item') {
      return ListItemNode(
        id: id,
        itemType: (data['type'] as String?) == 'ordered'
            ? ListItemType.ordered
            : ListItemType.unordered,
        text: attributedText,
        indent: data['indent'] as int? ?? 0,
      );
    }
    if (type == 'divider') {
      return HorizontalRuleNode(id: id);
    }
    if (type == 'corrupted') {
      return ParagraphNode(
        id: id,
        text: AttributedText(
          'Conteúdo indisponível — Erro de Sincronização',
          AttributedSpans(
            attributions: [
              const SpanMarker(
                attribution: corruptedAttribution,
                offset: 0,
                markerType: SpanMarkerType.start,
              ),
              const SpanMarker(
                attribution: corruptedAttribution,
                offset: 44,
                markerType: SpanMarkerType.end,
              ),
            ],
          ),
        ),
        metadata: {'blockType': corruptedAttribution},
      );
    }
    if (type == 'header') {
      final level = data['level'] as int? ?? 1;
      final blockType = switch (level) {
        1 => header1Attribution,
        2 => header2Attribution,
        3 => header3Attribution,
        4 => header4Attribution,
        5 => header5Attribution,
        _ => header6Attribution,
      };
      return ParagraphNode(
        id: id,
        text: attributedText,
        metadata: {'blockType': blockType},
      );
    }
    if (type == 'image') {
      return ImageNode(
        id: id,
        imageUrl: data['url'] as String? ?? '',
        altText: data['alt'] as String? ?? '',
      );
    }
    return ParagraphNode(id: id, text: attributedText);
  }

  static SpanMarker parseSpan(Map<String, dynamic> spanMap) {
    return SpanMarker(
      attribution: _attributionFromName(spanMap['attribution'] as String),
      offset: spanMap['start'] as int,
      markerType: SpanMarkerType.start,
    );
  }

  static AttributedSpans deserializeSpans(List spansJson) {
    final list = <SpanMarker>[];
    for (final s in spansJson) {
      final m = s as Map<String, dynamic>;
      final end = m['end'] as int;
      final parsed = parseSpan(m);
      list.add(parsed);
      list.add(
        SpanMarker(
          attribution: parsed.attribution,
          offset: end,
          markerType: SpanMarkerType.end,
        ),
      );
    }
    return AttributedSpans(attributions: list);
  }

  static AttributedText _deserializeAttributedText(Map<String, dynamic> data) {
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

      // Spans written before version 2 stored SuperEditor's inclusive marker
      // offset. Version 2 persists an exclusive end offset.
      final end = data['spansVersion'] == 2 ? storedEnd : storedEnd + 1;
      final safeStart = start.clamp(0, text.length);
      final safeEnd = end.clamp(safeStart, text.length);
      if (safeEnd > safeStart) {
        spans.addAttribution(
          newAttribution: _attributionFromName(attributionName),
          start: safeStart,
          end: safeEnd - 1,
        );
      }
    }

    return AttributedText(text, spans);
  }

  static DocumentNode? _nodeFromData(NoteNode node) {
    return _createNode(id: node.id, type: node.type, data: node.data);
  }

  static String? nodeType(DocumentNode node) {
    if (node is ParagraphNode) {
      final blockType = node.getMetadataValue('blockType') as Attribution?;
      if (blockType == corruptedAttribution) return 'corrupted';
      if (blockType == null || blockType.id == 'paragraph') return 'paragraph';
      if (blockType == blockquoteAttribution) return 'blockquote';
      return 'header';
    }
    if (node is TaskNode) return 'task';
    if (node is ListItemNode) return 'list_item';
    if (node is HorizontalRuleNode) return 'divider';
    if (node is ImageNode) return 'image';
    if (node is DocumentAttachmentNode) return 'attachment';
    return null;
  }

  static bool isNodeEquivalent(DocumentNode existingNode, NoteNode incoming) {
    final existingAttribution = nodeType(existingNode);
    if (existingAttribution != incoming.type) return false;

    // 1. Plain text comparison for all text nodes
    if (existingNode is TextNode) {
      final existingText = existingNode.text.toPlainText();
      final incomingText = incoming.data['text'] as String? ?? '';
      if (existingText != incomingText) return false;
    }

    // 2. Type-specific semantic checks
    if (existingNode is TaskNode && incoming.type == 'task') {
      final existingDataMap = nodeData(existingNode);
      try {
        final existingEntry = YjsTaskEntry.fromJson(existingDataMap);
        final incomingEntry = YjsTaskEntry.fromJson(incoming.data);
        return existingEntry == incomingEntry;
      } catch (_) {
        return false;
      }
    }

    if (existingNode is ListItemNode && incoming.type == 'list_item') {
      final existingType = existingNode.type;
      final incomingTypeStr = incoming.data['type'] as String? ?? 'unordered';
      final resolvedIncomingType = incomingTypeStr == 'ordered'
          ? ListItemType.ordered
          : ListItemType.unordered;
      if (existingType != resolvedIncomingType) return false;

      final existingIndent = existingNode.indent;
      final incomingIndent = incoming.data['indent'] as int? ?? 0;
      if (existingIndent != incomingIndent) return false;

      return true;
    }

    if (existingNode is ParagraphNode && incoming.type == 'header') {
      final blockType = existingNode.metadata['blockType'] as Attribution?;
      final level = incoming.data['level'] as int? ?? 1;
      final expectedBlockType = switch (level) {
        1 => header1Attribution,
        2 => header2Attribution,
        3 => header3Attribution,
        4 => header4Attribution,
        5 => header5Attribution,
        _ => header6Attribution,
      };
      return blockType == expectedBlockType;
    }

    if (existingNode is ParagraphNode && incoming.type == 'paragraph') {
      // Already checked plain text, and it's a normal paragraph
      return true;
    }

    if (existingNode is ImageNode && incoming.type == 'image') {
      return existingNode.imageUrl == (incoming.data['url'] as String? ?? '') &&
          existingNode.altText == (incoming.data['alt'] as String? ?? '');
    }

    if (existingNode is HorizontalRuleNode && incoming.type == 'divider') {
      return true;
    }

    // Fallback for any other custom types
    final existingDataMap = nodeData(existingNode);
    return deepEquals(existingDataMap, incoming.data);
  }

  static bool deepEquals(dynamic a, dynamic b) {
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (int i = 0; i < a.length; i++) {
        if (!deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key)) return false;
        if (!deepEquals(a[key], b[key])) return false;
      }
      return true;
    }
    return a == b;
  }
}

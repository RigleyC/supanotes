import 'dart:convert';
import 'dart:developer' as dev;

import 'package:collection/collection.dart';
import 'package:super_editor/super_editor.dart';

import 'attachment_nodes.dart';
import 'note_node.dart';

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
            spansList[i]['end'] = span.offset;
            break;
          }
        }
      }
    }
    return {'text': text.toPlainText(), 'spans': spansList};
  }

  static String nodeData(DocumentNode node) {
    if (node is TaskNode) {
      return jsonEncode({
        ..._serializeAttributedText(node.text),
        'indent': node.indent,
      });
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
        return jsonEncode({
          ..._serializeAttributedText(node.text),
          'level': level,
        });
      }
      if (blockType == blockquoteAttribution) {
        return jsonEncode({..._serializeAttributedText(node.text)});
      }
      return jsonEncode({..._serializeAttributedText(node.text)});
    }
    if (node is ListItemNode) {
      return jsonEncode({
        ..._serializeAttributedText(node.text),
        'type': node.type == ListItemType.ordered ? 'ordered' : 'unordered',
        'indent': node.indent,
      });
    }
    if (node is TextNode) {
      return jsonEncode({..._serializeAttributedText(node.text)});
    }
    if (node is ImageNode) {
      return jsonEncode({'url': node.imageUrl, 'alt': node.altText});
    }
    if (node is HorizontalRuleNode) {
      return '{}';
    }
    if (node is DocumentAttachmentNode) {
      return jsonEncode({'id': node.id});
    }
    if (node is RichLinkNode) {
      return jsonEncode({
        'id': node.id,
        if (node.url != null) 'url': node.url,
        if (node.title != null) 'title': node.title,
        if (node.description != null) 'description': node.description,
        if (node.imageUrl != null) 'image_url': node.imageUrl,
        if (node.domain != null) 'domain': node.domain,
      });
    }
    return '{}';
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
    final type = schema.type;
    final data = jsonDecode(schema.data) as Map<String, dynamic>;
    final text = data['text'] as String? ?? '';
    final spans = data['spans'] as List? ?? [];
    final attributedText = AttributedText(text, deserializeSpans(spans));

    if (type == 'task') {
      return TaskNode(
        id: schema.id,
        text: attributedText,
        isComplete: data['completed'] as bool? ?? false,
        indent: data['indent'] as int? ?? 0,
      );
    }
    if (type == 'list_item') {
      return ListItemNode(
        id: schema.id,
        itemType: (data['type'] as String?) == 'ordered'
            ? ListItemType.ordered
            : ListItemType.unordered,
        text: attributedText,
        indent: data['indent'] as int? ?? 0,
      );
    }
    if (type == 'divider') {
      return HorizontalRuleNode(id: schema.id);
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
        id: schema.id,
        text: attributedText,
        metadata: {'blockType': blockType},
      );
    }
    if (type == 'image') {
      return ImageNode(
        id: schema.id,
        imageUrl: data['url'] as String? ?? '',
        altText: data['alt'] as String? ?? '',
      );
    }
    return ParagraphNode(id: schema.id, text: attributedText);
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
      final end = spanMap['end'] as int?;

      if (attributionName == null || start == null || end == null || end == -1) {
        continue;
      }

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
    Map<String, dynamic> data;
    try {
      data = node.data.isNotEmpty
          ? jsonDecode(node.data) as Map<String, dynamic>
          : <String, dynamic>{};
    } catch (_) {
      try {
        data =
            jsonDecode(utf8.decode(base64Decode(node.data)))
                as Map<String, dynamic>;
      } catch (_) {
        data = <String, dynamic>{};
      }
    }

    switch (node.type) {
      case 'header':
        final level = data['level'] as int? ?? 1;
        NamedAttribution blockType = header1Attribution;
        if (level == 2) blockType = header2Attribution;
        if (level == 3) blockType = header3Attribution;
        if (level == 4) blockType = header4Attribution;
        if (level == 5) blockType = header5Attribution;
        if (level == 6) blockType = header6Attribution;
        return ParagraphNode(
          id: node.id,
          text: _deserializeAttributedText(data),
          metadata: {'blockType': blockType},
        );
      case 'blockquote':
        return ParagraphNode(
          id: node.id,
          text: _deserializeAttributedText(data),
          metadata: {'blockType': blockquoteAttribution},
        );
      case 'list_item':
        final typeStr = data['type'] as String? ?? 'unordered';
        return ListItemNode(
          id: node.id,
          itemType: typeStr == 'ordered'
              ? ListItemType.ordered
              : ListItemType.unordered,
          text: _deserializeAttributedText(data),
          indent: data['indent'] as int? ?? 0,
        );
      case 'paragraph':
        return ParagraphNode(
          id: node.id,
          text: _deserializeAttributedText(data),
        );
      case 'task':
        return TaskNode(
          id: node.id,
          text: _deserializeAttributedText(data),
          isComplete: data['completed'] == true || data['isComplete'] == true,
          indent: data['indent'] as int? ?? 0,
        );
      case 'divider':
        return HorizontalRuleNode(id: node.id);
      case 'attachment':
        final attachmentId = data['id'] as String? ?? node.id;
        return DocumentAttachmentNode(id: attachmentId);
      case 'image':
        return ImageNode(
          id: node.id,
          imageUrl: data['url'] as String? ?? '',
          altText: data['alt'] as String? ?? '',
        );
      default:
        return ParagraphNode(
          id: node.id,
          text: _deserializeAttributedText(data),
        );
    }
  }

  static String? _existingAttribution(DocumentNode node) {
    if (node is ParagraphNode) {
      final blockType = node.getMetadataValue('blockType') as Attribution?;
      if (blockType == null) return 'paragraph';
      if (blockType == blockquoteAttribution) return 'blockquote';
      return 'header';
    }
    if (node is TaskNode) return 'task';
    if (node is ListItemNode) return 'list_item';
    if (node is HorizontalRuleNode) return 'divider';
    return null;
  }

  static bool isNodeEquivalent(DocumentNode existingNode, NoteNode incoming) {
    final existingAttribution = _existingAttribution(existingNode);
    if (existingAttribution != incoming.type) return false;

    if (existingNode is TextNode &&
        incoming.type != 'image' &&
        incoming.type != 'divider') {
      final data = jsonDecode(incoming.data) as Map<String, dynamic>;
      if (existingNode.text.toPlainText() != (data['text'] as String? ?? '')) {
        return false;
      }
    }

    final existingDataStr = nodeData(existingNode);
    try {
      final existingData = jsonDecode(existingDataStr) as Map<String, dynamic>;
      final incomingData = jsonDecode(incoming.data) as Map<String, dynamic>;
      final isEq = const DeepCollectionEquality().equals(existingData, incomingData);
      if (!isEq) {
        dev.log(
          '[NodeCodec] NODE NOT EQUIVALENT ID=${incoming.id} TYPE=${incoming.type}\n'
          'Existing: $existingData\n'
          'Incoming: $incomingData',
          name: 'SyncService',
        );
      }
      return isEq;
    } catch (_) {
      return false;
    }
  }
}

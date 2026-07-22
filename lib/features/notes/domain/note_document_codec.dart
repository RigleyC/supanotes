import 'package:super_editor/super_editor.dart';

import 'attachment_nodes.dart';
import 'note_node.dart';

const header4Attribution = NamedAttribution('header4');
const header5Attribution = NamedAttribution('header5');
const header6Attribution = NamedAttribution('header6');
const corruptedAttribution = NamedAttribution('corrupted');

class NoteDocumentCodec {
  const NoteDocumentCodec();

  // ---------------------------------------------------------------------------
  // Static Helper Methods (formerly NodeCodec static methods)
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

  static Map<String, dynamic> serializeAttributedText(AttributedText text) {
    final spansList = <Map<String, dynamic>>[];
    for (final span in text.spans.markers) {
      if (span.isStart) {
        if (span.attribution.id == 'composing') continue;
        spansList.add({
          'attribution': attributionToName(span.attribution),
          'start': span.offset,
          'end': -1,
        });
      } else {
        if (span.attribution.id == 'composing') continue;
        final name = attributionToName(span.attribution);
        for (int i = spansList.length - 1; i >= 0; i--) {
          if (spansList[i]['attribution'] == name &&
              spansList[i]['end'] == -1) {
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
      return {...serializeAttributedText(node.text), 'indent': node.indent};
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
        return {...serializeAttributedText(node.text), 'level': level};
      }
      if (blockType == blockquoteAttribution) {
        return {...serializeAttributedText(node.text)};
      }
      return {...serializeAttributedText(node.text)};
    }
    if (node is ListItemNode) {
      return {
        ...serializeAttributedText(node.text),
        'type': node.type == ListItemType.ordered ? 'ordered' : 'unordered',
        'indent': node.indent,
      };
    }
    if (node is TextNode) {
      return {...serializeAttributedText(node.text)};
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
      final docNode = createNodeFromSchema(node);
      documentNodes.add(docNode);
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
    return createNode(id: schema.id, type: schema.type, data: schema.data);
  }

  static DocumentNode createNode({
    required String id,
    required String type,
    required Map<String, dynamic> data,
  }) {
    final attributedText = deserializeAttributedText(data);

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
      attribution: attributionFromNameStatic(spanMap['attribution'] as String),
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
      if (node.metadata.containsKey('dueDate')) {
        metadata['dueDate'] = node.metadata['dueDate'];
      }
      if (node.metadata.containsKey('recurrenceRule')) {
        metadata['recurrenceRule'] = node.metadata['recurrenceRule'];
      }
    } else if (node is HorizontalRuleNode) {
      type = 'divider';
    } else if (node is ListItemNode) {
      type = node.type == ListItemType.ordered ? 'orderedList' : 'bulletList';
      text = node.text;
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
      'content': deltaOps,
    };
    if (metadata.isNotEmpty) {
      result['metadata'] = _toJsonValue(metadata);
    }
    return result;
  }

  List<Map<String, dynamic>> encodeAttributedTextToDelta(AttributedText text) {
    final deltaOps = <Map<String, dynamic>>[];
    final plainText = text.toPlainText();
    if (plainText.isEmpty) return deltaOps;

    int pos = 0;
    while (pos < plainText.length) {
      final attrIds = _getAttrIdsAt(text, pos);
      int end = pos + 1;
      while (end < plainText.length) {
        if (setEquals(attrIds, _getAttrIdsAt(text, end))) {
          end++;
        } else {
          break;
        }
      }

      final Map<String, dynamic> attrs = {};
      for (final id in attrIds) {
        if (id != 'composing') {
          attrs[id] = true;
        }
      }

      final Map<String, dynamic> op = {
        'insert': plainText.substring(pos, end),
      };
      if (attrs.isNotEmpty) {
        op['attributes'] = attrs;
      }
      deltaOps.add(op);
      pos = end;
    }

    return deltaOps;
  }

  DocumentNode decodeNode(Map<String, dynamic> blockData) {
    final String nodeId = blockData['id'] as String? ?? Editor.createNodeId();
    String type = blockData['type'] as String? ?? 'paragraph';
    final List<dynamic>? content =
        (blockData['content'] ?? blockData['delta']) as List<dynamic>?;
    final Map<String, dynamic> metadata = Map<String, dynamic>.from(
      blockData['metadata'] as Map? ?? {},
    );
    if (type == 'paragraph' && metadata.containsKey('blockType')) {
      final rawBType = metadata['blockType'];
      if (rawBType is String) {
        type = rawBType;
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

    node.metadata.addAll(metadata);

    if (node is ParagraphNode) {
      final blockTypeAttr = attributionFromName(type) ??
          (metadata['blockType'] is String
              ? attributionFromName(metadata['blockType'] as String)
              : null);
      if (blockTypeAttr != null) {
        node.metadata['blockType'] = blockTypeAttr;
      }
    }
    return node;
  }

  DocumentNode decodeBlock(Map<String, dynamic> blockData) => decodeNode(blockData);

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

  List<Map<String, dynamic>> toOtBlocks(List<DocumentNode> nodes) {
    return nodes.map(encodeNode).toList();
  }

  DocumentNode createNodeFromBlockType({
    required String nodeId,
    required String type,
    required AttributedText text,
    bool isTaskComplete = false,
    ListItemType itemType = ListItemType.unordered,
    Map<String, dynamic>? metadata,
  }) {
    if (type == 'divider') {
      return HorizontalRuleNode(id: nodeId);
    }
    if (type == 'attachment') {
      return DocumentAttachmentNode(id: nodeId, metadata: metadata ?? {});
    }
    if (type == 'bulletList') {
      return ListItemNode(id: nodeId, itemType: ListItemType.unordered, text: text);
    }
    if (type == 'orderedList') {
      return ListItemNode(id: nodeId, itemType: ListItemType.ordered, text: text);
    }
    if (type == 'task') {
      return TaskNode(
        id: nodeId,
        text: text,
        isComplete: isTaskComplete,
        metadata: metadata,
      );
    }
    if (type == 'header1') {
      return ParagraphNode(
        id: nodeId,
        text: text,
        metadata: {'blockType': header1Attribution},
      );
    }
    if (type == 'header2') {
      return ParagraphNode(
        id: nodeId,
        text: text,
        metadata: {'blockType': header2Attribution},
      );
    }
    if (type == 'header3') {
      return ParagraphNode(
        id: nodeId,
        text: text,
        metadata: {'blockType': header3Attribution},
      );
    }
    if (type == 'quote') {
      return ParagraphNode(
        id: nodeId,
        text: text,
        metadata: {'blockType': blockquoteAttribution},
      );
    }
    return ParagraphNode(id: nodeId, text: text);
  }

  AttributedText attributedFromDelta(List<dynamic>? delta) {
    if (delta == null || delta.isEmpty) return AttributedText();
    final span = AttributedSpans();
    final buf = StringBuffer();
    for (final op in delta) {
      if (op is! Map) continue;
      final insert = op['insert'] as String?;
      if (insert == null || insert.isEmpty) continue;
      final start = buf.length;
      buf.write(insert);
      final attrs = op['attributes'] as Map<String, dynamic>?;
      if (attrs != null) {
        for (final entry in attrs.entries) {
          if (entry.value == true) {
            final attr = attributionFromId(entry.key);
            if (attr != null) {
              span.addAttribution(
                newAttribution: attr,
                start: start,
                end: buf.length,
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
    final srcText = source.toPlainText();
    final buf = StringBuffer();
    final resultAttrs = <int, Set<String>>{};

    int srcPos = 0;
    int destPos = 0;

    for (final op in ops) {
      if (op.containsKey('retain')) {
        final n = op['retain'] as int;
        if (srcPos + n > srcText.length) return null;
        final retainAttrs = op['attributes'] as Map<String, dynamic>?;
        for (int i = 0; i < n; i++) {
          buf.write(srcText[srcPos]);
          resultAttrs[destPos] = _getAttrIdsAt(source, srcPos);
          if (retainAttrs != null) {
            _applyAttrOverride(resultAttrs[destPos]!, retainAttrs);
          }
          srcPos++;
          destPos++;
        }
      } else if (op.containsKey('insert')) {
        final text = op['insert'] as String;
        final insertAttrs = op['attributes'] as Map<String, dynamic>?;
        for (int i = 0; i < text.length; i++) {
          buf.write(text[i]);
          resultAttrs[destPos] = <String>{};
          if (insertAttrs != null) {
            for (final entry in insertAttrs.entries) {
              if (entry.value == true) {
                resultAttrs[destPos]!.add(entry.key);
              }
            }
          }
          destPos++;
        }
      } else if (op.containsKey('delete')) {
        final n = op['delete'] as int;
        if (srcPos + n > srcText.length) return null;
        srcPos += n;
      } else {
        return null;
      }
    }

    while (srcPos < srcText.length) {
      buf.write(srcText[srcPos]);
      resultAttrs[destPos] = _getAttrIdsAt(source, srcPos);
      srcPos++;
      destPos++;
    }

    return _buildAttributedFromAttrs(buf.toString(), resultAttrs);
  }

  DocumentNode replaceTextNode(TextNode oldNode, AttributedText newText) {
    if (oldNode is ParagraphNode) {
      return ParagraphNode(
        id: oldNode.id,
        text: newText,
        metadata: Map<String, dynamic>.from(oldNode.metadata),
      );
    }
    if (oldNode is ListItemNode) {
      return ListItemNode(
        id: oldNode.id,
        itemType: oldNode.type,
        text: newText,
        indent: oldNode.indent,
      );
    }
    if (oldNode is TaskNode) {
      return TaskNode(
        id: oldNode.id,
        text: newText,
        isComplete: oldNode.isComplete,
        indent: oldNode.indent,
      );
    }
    return ParagraphNode(id: oldNode.id, text: newText);
  }

  String? blockTypeName(DocumentNode node) {
    if (node is ParagraphNode) {
      final blockType = node.getMetadataValue('blockType') as Attribution?;
      if (blockType == header1Attribution) return 'header1';
      if (blockType == header2Attribution) return 'header2';
      if (blockType == header3Attribution) return 'header3';
      if (blockType == blockquoteAttribution) return 'quote';
      return null;
    }
    if (node is ListItemNode) {
      return node.type == ListItemType.ordered ? 'orderedList' : 'bulletList';
    }
    if (node is TaskNode) return 'task';
    if (node is HorizontalRuleNode) return 'divider';
    return null;
  }

  Attribution? attributionFromId(String id) {
    if (id == 'bold') return boldAttribution;
    if (id == 'italics') return italicsAttribution;
    if (id == 'strikethrough') return strikethroughAttribution;
    if (id == 'underline') return underlineAttribution;
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

  bool mapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }

  bool setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final e in a) {
      if (!b.contains(e)) return false;
    }
    return true;
  }

  int findSpanEnd(Iterable<SpanMarker> markers, SpanMarker startMarker) {
    for (final marker in markers) {
      if (marker.attribution.id == startMarker.attribution.id &&
          marker.markerType == SpanMarkerType.end &&
          marker.offset >= startMarker.offset) {
        return marker.offset;
      }
    }
    return -1;
  }

  Set<String> _getAttrIdsAt(AttributedText text, int pos) {
    final ids = <String>{};
    for (final marker in text.spans.markers) {
      if (marker.markerType == SpanMarkerType.start &&
          marker.offset <= pos &&
          marker.attribution.id != 'composing') {
        final spanEnd = findSpanEnd(text.spans.markers, marker);
        if (spanEnd > pos) {
          ids.add(marker.attribution.id);
        }
      }
    }
    return ids;
  }

  void _applyAttrOverride(Set<String> dest, Map<String, dynamic> attrs) {
    for (final entry in attrs.entries) {
      if (entry.value == true) {
        dest.add(entry.key);
      } else if (entry.value == null) {
        dest.remove(entry.key);
      }
    }
  }

  AttributedText _buildAttributedFromAttrs(
    String text,
    Map<int, Set<String>> attrs,
  ) {
    if (text.isEmpty) return AttributedText();
    final span = AttributedSpans();
    int pos = 0;
    while (pos < text.length) {
      final currentAttrs = attrs[pos] ?? <String>{};
      int end = pos + 1;
      while (end < text.length) {
        if (setEquals(currentAttrs, attrs[end] ?? <String>{})) {
          end++;
        } else {
          break;
        }
      }
      for (final id in currentAttrs) {
        final attr = attributionFromId(id);
        if (attr != null) {
          span.addAttribution(
            newAttribution: attr,
            start: pos,
            end: end,
          );
        }
      }
      pos = end;
    }
    return AttributedText(text, span);
  }
}

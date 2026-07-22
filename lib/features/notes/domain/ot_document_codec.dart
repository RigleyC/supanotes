import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/debug/note_sync_debug.dart';
import 'attachment_nodes.dart';

class OtDocumentCodec {
  const OtDocumentCodec();

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

  /// Converts a single [DocumentNode] to its OT block JSON representation.
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
    return {
      'id': blockId,
      'type': type,
      'delta': deltaOps,
      'metadata': _toJsonValue(metadata),
    };
  }

  /// Creates a [DocumentNode] from an OT block JSON object.
  DocumentNode decodeNode(Map<String, dynamic> blockJson) {
    final String nodeId = blockJson['id'] as String? ?? '';
    final String type = blockJson['type'] as String? ?? 'paragraph';
    final List<dynamic>? deltaList = blockJson['delta'] as List<dynamic>?;
    final metadata = Map<String, dynamic>.from(
      blockJson['metadata'] as Map? ?? {},
    );
    final blockType = metadata['blockType'];
    if (blockType is String) {
      metadata['blockType'] = attributionFromId(blockType);
    }

    final AttributedText text = attributedFromDelta(deltaList);

    switch (type) {
      case 'divider':
        return HorizontalRuleNode(id: nodeId);
      case 'bulletList':
        return ListItemNode(
          id: nodeId,
          itemType: ListItemType.unordered,
          text: text,
        );
      case 'orderedList':
        return ListItemNode(
          id: nodeId,
          itemType: ListItemType.ordered,
          text: text,
        );
      case 'task':
        final isCompleted = metadata['isCompleted'] as bool? ?? false;
        final taskNode = TaskNode(
          id: nodeId,
          text: text,
          isComplete: isCompleted,
          metadata: metadata,
        );
        return taskNode;
      case 'attachment':
        return DocumentAttachmentNode(id: nodeId, metadata: metadata);
      case 'rich_link':
        return RichLinkNode(
          id: nodeId,
          url: metadata['url'] as String?,
          title: metadata['title'] as String?,
          description: metadata['description'] as String?,
          imageUrl: metadata['imageUrl'] as String?,
          metadata: metadata,
        );
      case 'header1':
        return ParagraphNode(
          id: nodeId,
          text: text,
          metadata: {'blockType': header1Attribution, ...metadata},
        );
      case 'header2':
        return ParagraphNode(
          id: nodeId,
          text: text,
          metadata: {'blockType': header2Attribution, ...metadata},
        );
      case 'header3':
        return ParagraphNode(
          id: nodeId,
          text: text,
          metadata: {'blockType': header3Attribution, ...metadata},
        );
      case 'quote':
        return ParagraphNode(
          id: nodeId,
          text: text,
          metadata: {'blockType': blockquoteAttribution, ...metadata},
        );
      case 'paragraph':
      default:
        return ParagraphNode(id: nodeId, text: text, metadata: metadata);
    }
  }

  DocumentNode createNodeFromBlockType({
    required String nodeId,
    required String type,
    required AttributedText text,
    bool isTaskComplete = false,
  }) {
    if (type == 'divider') {
      return HorizontalRuleNode(id: nodeId);
    }
    if (type == 'bulletList') {
      return ListItemNode(
        id: nodeId,
        itemType: ListItemType.unordered,
        text: text,
      );
    }
    if (type == 'orderedList') {
      return ListItemNode(
        id: nodeId,
        itemType: ListItemType.ordered,
        text: text,
      );
    }
    if (type == 'task') {
      return TaskNode(id: nodeId, text: text, isComplete: isTaskComplete);
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

  AttributedText? applyDeltaToText(
    AttributedText source,
    List<Map<String, dynamic>> ops,
  ) {
    final srcText = source.toPlainText();
    NoteSyncDebug.log(
      'codec.apply_delta.begin',
      fields: {
        'sourceLength': srcText.length,
        'source': NoteSyncDebug.preview(srcText),
        'operations': NoteSyncDebug.payloadSummary({'ops': ops}),
      },
    );
    final buf = StringBuffer();
    final resultAttrs = <int, Set<String>>{};

    int srcPos = 0;
    int destPos = 0;

    for (final op in ops) {
      if (op.containsKey('retain')) {
        final n = op['retain'] as int;
        if (srcPos + n > srcText.length) {
          NoteSyncDebug.log(
            'codec.apply_delta.invalid_retain',
            fields: {
              'sourceLength': srcText.length,
              'sourcePosition': srcPos,
              'retain': n,
            },
          );
          return null;
        }
        final retainAttrs = op['attributes'] as Map<String, dynamic>?;
        for (int i = 0; i < n; i++) {
          buf.write(srcText[srcPos]);
          final curAttrs = <String>{};
          for (final marker in source.spans.markers) {
            if (marker.markerType == SpanMarkerType.start &&
                marker.offset <= srcPos) {
              final end = findSpanEnd(source.spans.markers, marker);
              if (end > srcPos && marker.attribution.id != 'composing') {
                curAttrs.add(marker.attribution.id);
              }
            }
          }
          if (retainAttrs != null) {
            for (final entry in retainAttrs.entries) {
              if (entry.value == true) {
                curAttrs.add(entry.key);
              } else if (entry.value == false) {
                curAttrs.remove(entry.key);
              }
            }
          }
          if (curAttrs.isNotEmpty) {
            resultAttrs[destPos] = curAttrs;
          }
          srcPos++;
          destPos++;
        }
      } else if (op.containsKey('delete')) {
        final n = op['delete'] as int;
        if (srcPos + n > srcText.length) {
          NoteSyncDebug.log(
            'codec.apply_delta.invalid_delete',
            fields: {
              'sourceLength': srcText.length,
              'sourcePosition': srcPos,
              'delete': n,
            },
          );
          return null;
        }
        srcPos += n;
      } else if (op.containsKey('insert')) {
        final str = op['insert'] as String;
        final insertAttrs = op['attributes'] as Map<String, dynamic>?;
        final curAttrs = <String>{};
        if (insertAttrs != null) {
          for (final entry in insertAttrs.entries) {
            if (entry.value == true) {
              curAttrs.add(entry.key);
            }
          }
        }
        for (int i = 0; i < str.length; i++) {
          buf.write(str[i]);
          if (curAttrs.isNotEmpty) {
            resultAttrs[destPos] = Set<String>.from(curAttrs);
          }
          destPos++;
        }
      }
    }

    while (srcPos < srcText.length) {
      buf.write(srcText[srcPos]);
      final curAttrs = <String>{};
      for (final marker in source.spans.markers) {
        if (marker.markerType == SpanMarkerType.start &&
            marker.offset <= srcPos) {
          final end = findSpanEnd(source.spans.markers, marker);
          if (end > srcPos && marker.attribution.id != 'composing') {
            curAttrs.add(marker.attribution.id);
          }
        }
      }
      if (curAttrs.isNotEmpty) {
        resultAttrs[destPos] = curAttrs;
      }
      srcPos++;
      destPos++;
    }

    final outPlainText = buf.toString();
    final outSpan = AttributedSpans();

    int pos = 0;
    while (pos < outPlainText.length) {
      final active = resultAttrs[pos] ?? <String>{};
      int runEnd = pos + 1;
      while (runEnd < outPlainText.length) {
        final next = resultAttrs[runEnd] ?? <String>{};
        if (!setEquals(active, next)) break;
        runEnd++;
      }
      for (final attrId in active) {
        final attr = attributionFromId(attrId);
        if (attr != null) {
          outSpan.addAttribution(newAttribution: attr, start: pos, end: runEnd);
        }
      }
      pos = runEnd;
    }

    NoteSyncDebug.log(
      'codec.apply_delta.end',
      fields: {
        'resultLength': outPlainText.length,
        'result': NoteSyncDebug.preview(outPlainText),
      },
    );
    return AttributedText(outPlainText, outSpan);
  }

  /// Converts Quill-style delta ops to [AttributedText].
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

  List<Map<String, dynamic>> encodeAttributedTextToDelta(AttributedText text) {
    final plainText = text.toPlainText();
    if (plainText.isEmpty) return [];

    final ops = <Map<String, dynamic>>[];
    int pos = 0;

    while (pos < plainText.length) {
      final activeAttrs = <String>{};
      for (final marker in text.spans.markers) {
        if (marker.markerType == SpanMarkerType.start && marker.offset <= pos) {
          final end = findSpanEnd(text.spans.markers, marker);
          if (end > pos && marker.attribution.id != 'composing') {
            activeAttrs.add(marker.attribution.id);
          }
        }
      }

      int runEnd = pos + 1;
      while (runEnd < plainText.length) {
        final currentAttrs = <String>{};
        for (final marker in text.spans.markers) {
          if (marker.markerType == SpanMarkerType.start &&
              marker.offset <= runEnd) {
            final end = findSpanEnd(text.spans.markers, marker);
            if (end > runEnd && marker.attribution.id != 'composing') {
              currentAttrs.add(marker.attribution.id);
            }
          }
        }
        if (!setEquals(activeAttrs, currentAttrs)) break;
        runEnd++;
      }

      final op = <String, dynamic>{'insert': plainText.substring(pos, runEnd)};
      if (activeAttrs.isNotEmpty) {
        final attrsMap = <String, dynamic>{};
        for (final a in activeAttrs) {
          attrsMap[a] = true;
        }
        op['attributes'] = attrsMap;
      }
      ops.add(op);
      pos = runEnd;
    }
    return ops;
  }

  int findSpanEnd(Iterable<SpanMarker> markers, SpanMarker startMarker) {
    for (final m in markers) {
      if (m.markerType == SpanMarkerType.end &&
          m.attribution == startMarker.attribution &&
          m.offset >= startMarker.offset) {
        return m.offset + 1;
      }
    }
    return 999999;
  }

  bool setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  Attribution? attributionFromId(String id) {
    if (id == 'bold') return boldAttribution;
    if (id == 'italics') return italicsAttribution;
    if (id == 'strikethrough') return strikethroughAttribution;
    if (id == 'underline') return underlineAttribution;
    if (id == 'header1') return header1Attribution;
    if (id == 'header2') return header2Attribution;
    if (id == 'header3') return header3Attribution;
    if (id == 'blockquote') return blockquoteAttribution;
    return NamedAttribution(id);
  }
}

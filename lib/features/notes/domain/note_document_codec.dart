import 'package:super_editor/super_editor.dart';

class NoteDocumentCodec {
  DocumentNode createNodeFromBlockType({
    required String nodeId,
    required String type,
    required AttributedText text,
    bool isTaskComplete = false,
    ListItemType itemType = ListItemType.unordered,
  }) {
    if (type == 'divider') {
      return HorizontalRuleNode(id: nodeId);
    }
    if (type == 'bulletList') {
      return ListItemNode(id: nodeId, itemType: ListItemType.unordered, text: text);
    }
    if (type == 'orderedList') {
      return ListItemNode(id: nodeId, itemType: ListItemType.ordered, text: text);
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

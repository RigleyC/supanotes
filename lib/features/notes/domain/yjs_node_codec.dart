import 'dart:convert';

import 'package:dart_crdt/dart_crdt.dart';

import 'note_node.dart';

NoteNode? noteNodeFromYDoc(Doc doc, String key, {String? noteIdOverride}) {
  final nodesMap = doc.getMap('nodes');
  final raw = nodesMap.getAttr(key);
  if (raw is! String) return null;
  try {
    final meta = jsonDecode(raw) as Map<String, dynamic>;
    final nodeId = meta['id'] as String;
    final ytext = doc.getText('content/$nodeId');
    final textContent = ytext.toPlainText();
    final data = Map<String, dynamic>.from(meta['data'] as Map? ?? {});
    if (textContent.isNotEmpty) {
      data['text'] = textContent;
    }
    final rawParentId = meta['parentId'] as String?;
    final resolvedParentId =
        (rawParentId == null || rawParentId.isEmpty) ? null : rawParentId;
    return NoteNode(
      id: nodeId,
      noteId: noteIdOverride ?? meta['noteId'] as String? ?? '',
      parentId: resolvedParentId,
      position: meta['position']?.toString() ?? 'a0',
      type: meta['type'] as String? ?? 'paragraph',
      data: jsonEncode(data),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (meta['createdAt'] as num?)?.toInt() ?? 0,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (meta['updatedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  } catch (_) {
    return null;
  }
}

List<NoteNode> noteNodesFromDoc(Doc doc, {String? noteIdOverride}) {
  final nodes = <NoteNode>[];
  final nodesMap = doc.getMap('nodes');
  for (final key in nodesMap.attrKeys) {
    final node = noteNodeFromYDoc(doc, key, noteIdOverride: noteIdOverride);
    if (node != null) nodes.add(node);
  }

  nodes.sort((a, b) => a.position.compareTo(b.position));
  return nodes;
}

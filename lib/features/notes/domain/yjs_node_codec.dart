import 'dart:convert';

import 'package:yjs_dart/yjs_dart.dart';

import 'note_node.dart';

NoteNode? noteNodeFromYDoc(Doc doc, String key, {String? noteIdOverride}) {
  final nodesMap = doc.getMap<Object>('nodes')!;
  final raw = nodesMap.get(key);
  if (raw is! String) return null;
  try {
    final meta = jsonDecode(raw) as Map<String, dynamic>;
    final nodeId = meta['id'] as String;
    String textContent = '';
    try {
      final ytext = doc.getText('content/$nodeId');
      if (ytext != null) {
        textContent = ytext.toString();
      }
    } catch (e) {
      // Fallback if the type was corrupted (e.g. instantiated as YMap).
      // We must not skip the node entirely, otherwise fractional indexing desyncs!
      textContent = '';
    }
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
  final nodesMap = doc.getMap<Object>('nodes')!;
  for (final key in nodesMap.keys) {
    final node = noteNodeFromYDoc(doc, key, noteIdOverride: noteIdOverride);
    if (node != null) nodes.add(node);
  }

  nodes.sort((a, b) => a.position.compareTo(b.position));
  return nodes;
}

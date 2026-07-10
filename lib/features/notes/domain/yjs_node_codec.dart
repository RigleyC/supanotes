import 'dart:convert';

import 'package:dart_crdt/dart_crdt.dart';

import '../../../core/database/database.dart';

Map<String, dynamic> parseNodeData(NoteNode node) {
  if (node.data.isEmpty) return {};
  try {
    return jsonDecode(node.data) as Map<String, dynamic>;
  } catch (_) {
    return {};
  }
}

String extractTextFromData(Map<String, dynamic> data) {
  return data['text'] as String? ?? '';
}

Map<String, dynamic> buildYjsNodeMeta(NoteNode node, Map<String, dynamic> data) {
  return {
    'id': node.id,
    'parentId': node.parentId,
    'position': node.position,
    'type': node.type,
    'data': data,
    'createdAt': node.createdAt.millisecondsSinceEpoch.toDouble(),
  };
}

List<NoteNode> noteNodesFromDoc(Doc doc, {String? noteIdOverride}) {
  final nodes = <NoteNode>[];
  final nodesMap = doc.getMap('nodes');
  for (final key in nodesMap.attrKeys) {
    final raw = nodesMap.getAttr(key);
    if (raw is! String) continue;
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
      nodes.add(NoteNode(
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
        isDirty: false,
      ));
    } catch (_) {
      continue;
    }
  }

  nodes.sort((a, b) => a.position.compareTo(b.position));
  return nodes;
}

import 'dart:convert';

import 'package:yjs_dart/yjs_dart.dart';

import '../../../core/database/database.dart';

List<NoteNode> noteNodesFromDoc(Doc doc, {String? noteIdOverride}) {
  final nodes = <NoteNode>[];
  final nodesMap = doc.getMap('nodes');
  if (nodesMap == null) return nodes;

  for (final key in nodesMap.keys) {
    final raw = nodesMap.get(key);
    if (raw is! String) continue;
    try {
      final meta = jsonDecode(raw) as Map<String, dynamic>;
      final nodeId = meta['id'] as String;
      final ytext = doc.getText('content/$nodeId');
      final textContent = ytext?.toString() ?? '';
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
        position: (meta['position'] as num?)?.toDouble() ?? 0.0,
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

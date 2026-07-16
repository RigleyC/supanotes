import 'dart:convert';

import 'package:yjs_dart/yjs_dart.dart';

import 'note_node.dart';

NoteNode? _readNodeFromYMap(Doc doc, String key, YMap nodeMap, {String? noteIdOverride}) {
  final nodeId = nodeMap.get('id') as String?;
  if (nodeId == null) return null;

  String textContent = '';
  try {
    final ytext = doc.getText('content/$nodeId');
    if (ytext != null) {
      textContent = ytext.toString();
    }
  } catch (e) {
    textContent = '';
  }

  final rawData = nodeMap.get('data');
  final data = rawData is String
      ? Map<String, dynamic>.from(jsonDecode(rawData) as Map)
      : <String, dynamic>{};
  
  if (textContent.isNotEmpty) {
    data['text'] = textContent;
  }

  // Promote task fields from YMap top-level into data dict for backward compat
  final type = nodeMap.get('type') as String? ?? 'paragraph';
  if (type == 'task') {
    final completed = nodeMap.get('completed');
    if (completed is bool) data['completed'] = completed;
    final dueDate = nodeMap.get('dueDate');
    if (dueDate is String) data['dueDate'] = dueDate;
    final recurrence = nodeMap.get('recurrence');
    if (recurrence is String) data['recurrence'] = recurrence;
    final lastCompletedAt = nodeMap.get('lastCompletedAt');
    if (lastCompletedAt is String) data['lastCompletedAt'] = lastCompletedAt;
  }

  final rawParentId = nodeMap.get('parentId') as String?;
  final resolvedParentId =
      (rawParentId == null || rawParentId.isEmpty) ? null : rawParentId;
  return NoteNode(
    id: nodeId,
    noteId: noteIdOverride ?? '',
    parentId: resolvedParentId,
    position: nodeMap.get('position')?.toString() ?? 'a0',
    type: type,
    data: jsonEncode(data),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (nodeMap.get('createdAt') as num?)?.toInt() ?? 0,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      (nodeMap.get('updatedAt') as num?)?.toInt() ?? 0,
    ),
  );
}

NoteNode? _readNodeFromJsonString(Doc doc, String key, String raw, {String? noteIdOverride}) {
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

NoteNode? noteNodeFromYDoc(Doc doc, String key, {String? noteIdOverride}) {
  final nodesMap = doc.getMap<Object>('nodes')!;
  final raw = nodesMap.get(key);
  if (raw == null) return null;
  if (raw is YMap) return _readNodeFromYMap(doc, key, raw, noteIdOverride: noteIdOverride);
  if (raw is String) return _readNodeFromJsonString(doc, key, raw, noteIdOverride: noteIdOverride);
  return null;
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

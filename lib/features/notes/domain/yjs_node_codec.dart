import 'dart:convert';

import 'package:yjs_dart/yjs_dart.dart';

import 'note_node.dart';

String _readNodeTextContent(Doc doc, String nodeId) {
  try {
    final fallbackType = doc.getText('content_fixed/$nodeId');
    if (fallbackType != null) {
      final text = fallbackType.toString();
      if (text.isNotEmpty) return text;
    }
  } catch (_) {}

  try {
    final legacyType = doc.getText('content/$nodeId');
    if (legacyType != null) {
      return legacyType.toString();
    }
  } catch (_) {}

  return '';
}

NoteNode? _readNodeFromYMap(Doc doc, String key, YMap nodeMap) {
  final nodeId = nodeMap.get('id') as String?;
  if (nodeId == null) return null;

  String derivedType = nodeMap.get('type') as String? ?? 'paragraph';
  final textContent = _readNodeTextContent(doc, nodeId);

  if (textContent.isEmpty) {
    try {
      final fallbackType = doc.get('content/$nodeId');
      if (fallbackType is YMap) {
        if (derivedType == 'paragraph') {
          derivedType = 'corrupted';
        }
      }
    } catch (_) {}
  }

  final rawData = nodeMap.get('data');
  final data = rawData is String
      ? Map<String, dynamic>.from(jsonDecode(rawData) as Map)
      : <String, dynamic>{};
  
  if (textContent.isNotEmpty) {
    data['text'] = textContent;
  }

  // Promote task fields from YMap top-level or composite keys into data dict
  if (derivedType == 'task') {
    final nodesMap = doc.getMap<Object>('nodes');
    final completed = nodesMap?.get('$nodeId:completed') ?? nodeMap.get('completed');
    if (completed is bool) data['completed'] = completed;
    
    final dueDate = nodesMap?.get('$nodeId:dueDate') ?? nodeMap.get('dueDate');
    if (dueDate is String) data['dueDate'] = dueDate;
    
    final recurrence = nodesMap?.get('$nodeId:recurrence') ?? nodeMap.get('recurrence');
    if (recurrence is String) data['recurrence'] = recurrence;
    
    final lastCompletedAt = nodesMap?.get('$nodeId:lastCompletedAt') ?? nodeMap.get('lastCompletedAt');
    if (lastCompletedAt is String) data['lastCompletedAt'] = lastCompletedAt;
    
    final hasTime = nodesMap?.get('$nodeId:hasTime') ?? nodeMap.get('hasTime');
    if (hasTime is bool) data['hasTime'] = hasTime;
  }

  final rawParentId = nodeMap.get('parentId') as String?;
  final resolvedParentId =
      (rawParentId == null || rawParentId.isEmpty) ? null : rawParentId;
  return NoteNode(
    id: nodeId,
    noteId: '',
    parentId: resolvedParentId,
    position: nodeMap.get('position')?.toString() ?? 'a0',
    type: derivedType,
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
    String derivedType = meta['type'] as String? ?? 'paragraph';
    final textContent = _readNodeTextContent(doc, nodeId);

    if (textContent.isEmpty) {
      try {
        final fallbackType = doc.get('content/$nodeId');
        if (fallbackType is YMap) {
          if (derivedType == 'paragraph') {
            derivedType = 'corrupted';
          }
        }
      } catch (_) {}
    }
    final data = Map<String, dynamic>.from(meta['data'] as Map? ?? {});
    
    if (derivedType == 'task') {
      final nodesMap = doc.getMap<Object>('nodes');
      
      final completed = nodesMap?.get('$nodeId:completed') ?? data['completed'];
      if (completed is bool) data['completed'] = completed;
      
      final dueDate = nodesMap?.get('$nodeId:dueDate') ?? data['dueDate'];
      if (dueDate is String) data['dueDate'] = dueDate;
      
      final recurrence = nodesMap?.get('$nodeId:recurrence') ?? data['recurrence'];
      if (recurrence is String) data['recurrence'] = recurrence;
      
      final lastCompletedAt = nodesMap?.get('$nodeId:lastCompletedAt') ?? data['lastCompletedAt'];
      if (lastCompletedAt is String) data['lastCompletedAt'] = lastCompletedAt;
      
      final hasTime = nodesMap?.get('$nodeId:hasTime') ?? data['hasTime'];
      if (hasTime is bool) data['hasTime'] = hasTime;
    }

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
      type: derivedType,
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

NoteNode? noteNodeFromYDoc(Doc doc, String key) {
  final nodesMap = doc.getMap<Object>('nodes')!;
  final raw = nodesMap.get(key);
  if (raw == null) return null;
  if (raw is YMap) return _readNodeFromYMap(doc, key, raw);
  if (raw is String) return _readNodeFromJsonString(doc, key, raw);
  return null;
}

List<NoteNode> noteNodesFromDoc(Doc doc) {
  final nodes = <NoteNode>[];
  final nodesMap = doc.getMap<Object>('nodes')!;
  for (final key in nodesMap.keys) {
    final node = noteNodeFromYDoc(doc, key);
    if (node != null) nodes.add(node);
  }

  nodes.sort((a, b) => a.position.compareTo(b.position));
  return nodes;
}

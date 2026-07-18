import 'dart:convert';

import 'package:yjs_dart/yjs_dart.dart';

import 'note_node.dart';

String _readNodeTextContent(
  Doc doc,
  String nodeId, {
  Map<String, dynamic>? nodeData,
}) {
  // Mirror the backend projection logic: prefer the first non-empty YText
  // shared type, then fall back to the embedded text in the node data.
  // We guard calls to doc.getText with doc.share because getText creates an
  // empty type on demand, which would otherwise hide the data.text fallback.
  final fixedKey = 'content_fixed/$nodeId';
  if (doc.share.containsKey(fixedKey)) {
    try {
      final fallbackType = doc.getText(fixedKey);
      if (fallbackType != null) {
        final text = fallbackType.toString();
        if (text.isNotEmpty) return text;
      }
    } catch (_) {}
  }

  final contentKey = 'content/$nodeId';
  if (doc.share.containsKey(contentKey)) {
    try {
      final legacyType = doc.getText(contentKey);
      if (legacyType != null) {
        final text = legacyType.toString();
        if (text.isNotEmpty) return text;
      }
    } catch (_) {}
  }

  final dataText = nodeData?['text'] as String?;
  if (dataText != null && dataText.isNotEmpty) return dataText;

  return '';
}

NoteNode? _readNodeFromYMap(Doc doc, String key, YMap nodeMap) {
  final nodeId = nodeMap.get('id') as String?;
  if (nodeId == null) return null;

  String derivedType = nodeMap.get('type') as String? ?? 'paragraph';

  final rawData = nodeMap.get('data');
  final data = rawData is String
      ? Map<String, dynamic>.from(jsonDecode(rawData) as Map)
      : <String, dynamic>{};

  final textContent = _readNodeTextContent(doc, nodeId, nodeData: data);

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
    
    final reminder = nodesMap?.get('$nodeId:reminder') ?? nodeMap.get('reminder');
    if (reminder is String) data['reminder'] = reminder;
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
    data: data,
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

    final data = Map<String, dynamic>.from(meta['data'] as Map? ?? {});

    final textContent = _readNodeTextContent(doc, nodeId, nodeData: data);

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
      data: data,
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

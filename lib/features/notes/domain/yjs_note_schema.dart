import 'dart:convert';
import 'dart:developer' as dev;

import 'package:super_editor/super_editor.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'node_codec.dart';
import 'note_node.dart';

abstract final class YjsNoteSchema {
  static const nodesRoot = 'nodes';
  static String contentRoot(String id) => 'content/$id';

  static const taskCompletionsRoot = 'taskCompletions';
  static String taskCompletionKey(String taskId, String scheduledAtUtc) =>
      '$taskId:$scheduledAtUtc';

  static const fieldId = 'id';
  static const fieldType = 'type';
  static const fieldPosition = 'position';
  static const fieldParentId = 'parentId';
  static const fieldData = 'data';
  static const fieldCreatedAt = 'createdAt';
  static const fieldUpdatedAt = 'updatedAt';
  static const fieldCompleted = 'completed';
  static const fieldDueDate = 'dueDate';
  static const fieldHasTime = 'hasTime';
  static const fieldRecurrence = 'recurrence';
  static const fieldReminder = 'reminder';
  static const fieldLastCompletedAt = 'lastCompletedAt';

  static YMap requireNode(Doc doc, String id) {
    final nodesMap = doc.getMap<Object>(nodesRoot)!;
    final raw = nodesMap.get(id);
    if (raw is! YMap) {
      throw StateError('Node $id not found or not a YMap in YDoc');
    }
    return raw;
  }

  static NoteNode readNode(Doc doc, String id) {
    final nodeMap = requireNode(doc, id);
    final nodeId = nodeMap.get(fieldId) as String? ?? id;
    final type = nodeMap.get(fieldType) as String? ?? 'paragraph';

    final rawData = nodeMap.get(fieldData);
    final data = rawData is String
        ? Map<String, dynamic>.from(jsonDecode(rawData) as Map)
        : <String, dynamic>{};

    final textContent = readNodeTextContent(doc, nodeId);
    if (textContent.isNotEmpty) {
      data['text'] = textContent;
    }

    if (type == 'task') {
      _promoteTaskFields(nodeMap, data);
    }

    final rawParentId = nodeMap.get(fieldParentId) as String?;
    return NoteNode(
      id: nodeId,
      noteId: '',
      parentId: (rawParentId == null || rawParentId.isEmpty) ? null : rawParentId,
      position: nodeMap.get(fieldPosition)?.toString() ?? 'a0',
      type: type,
      data: data,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (nodeMap.get(fieldCreatedAt) as num?)?.toInt() ?? 0,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (nodeMap.get(fieldUpdatedAt) as num?)?.toInt() ?? 0,
      ),
    );
  }

  static void writeNode(Doc doc, DocumentNode node, {required String position}) {
    final nodesMap = doc.getMap<Object>(nodesRoot)!;
    final id = node.id;

    final existingRaw = nodesMap.get(id);
    YMap nodeMap;
    if (existingRaw is YMap) {
      nodeMap = existingRaw;
    } else {
      nodeMap = YMap<Object>();
      nodesMap.set(id, nodeMap);
    }

    final data = NodeCodec.nodeData(node);
    final createdAt = _readCreatedAt(existingRaw) ??
        DateTime.now().millisecondsSinceEpoch.toDouble();
    final parentId = _readParentId(existingRaw) ?? '';

    nodeMap.set(fieldId, id);
    nodeMap.set(fieldParentId, parentId);
    nodeMap.set(fieldPosition, position);
    nodeMap.set(fieldType, NodeCodec.nodeType(node) ?? 'paragraph');
    nodeMap.set(fieldData, jsonEncode(data));
    nodeMap.set(fieldCreatedAt, createdAt);

    if (node is TaskNode) {
      nodeMap.set(fieldCompleted, node.isComplete);
    }

    String text = '';
    if (node is TextNode) {
      text = node.text.toPlainText();
    }
    _writeNodeTextContent(doc, id, text);

    dev.log('[YjsNoteSchema] writeNode: id=$id type=${NodeCodec.nodeType(node)} position=$position textLen=${text.length}', name: 'YjsNoteSchema');
  }

  static void normalizeNode(Doc doc, String id) {
    final nodesMap = doc.getMap<Object>(nodesRoot)!;
    final raw = nodesMap.get(id);

    if (raw is YMap) {
      _normalizeYMapNode(doc, nodesMap, id, raw);
    } else if (raw is String) {
      _normalizeJsonStringNode(doc, nodesMap, id, raw);
    }
  }

  static void _normalizeYMapNode(
    Doc doc,
    YMap<Object> nodesMap,
    String id,
    YMap nodeMap,
  ) {
    final compositePrefix = '$id:';
    bool changed = false;

    for (final key in List<String>.from(nodesMap.keys)) {
      if (key.startsWith(compositePrefix)) {
        final fieldName = key.substring(compositePrefix.length);
        final value = nodesMap.get(key);
        if (value != null) {
          nodeMap.set(fieldName, value);
        }
        nodesMap.delete(key);
        changed = true;
      }
    }

    if (changed) {
      dev.log('[YjsNoteSchema] normalizeNode: migrated composite keys for id=$id', name: 'YjsNoteSchema');
    }
  }

  static void _normalizeJsonStringNode(
    Doc doc,
    YMap<Object> nodesMap,
    String id,
    String raw,
  ) {
    try {
      final meta = jsonDecode(raw) as Map<String, dynamic>;
      final nodeId = meta['id'] as String? ?? id;
      final nodeType = meta['type'] as String? ?? 'paragraph';
      final position = meta['position']?.toString() ?? 'a0';
      final createdAt = (meta['createdAt'] as num?)?.toDouble() ??
          DateTime.now().millisecondsSinceEpoch.toDouble();

      final nodeMap = YMap<Object>();
      nodeMap.set(fieldId, nodeId);
      nodeMap.set(fieldPosition, position);
      nodeMap.set(fieldType, nodeType);
      nodeMap.set(fieldCreatedAt, createdAt);

      final data = meta['data'] as Map<String, dynamic>? ?? {};
      nodeMap.set(fieldData, jsonEncode(data));

      if (meta['parentId'] is String) {
        nodeMap.set(fieldParentId, meta['parentId']);
      }

      final compositePrefix = '$id:';
      for (final key in List<String>.from(nodesMap.keys)) {
        if (key.startsWith(compositePrefix)) {
          final fieldName = key.substring(compositePrefix.length);
          final value = nodesMap.get(key);
          if (value != null) {
            nodeMap.set(fieldName, value);
          }
          nodesMap.delete(key);
        }
      }

      nodesMap.set(id, nodeMap);
      dev.log('[YjsNoteSchema] normalizeNode: migrated JSON string to YMap for id=$id', name: 'YjsNoteSchema');
    } catch (e) {
      dev.log('[YjsNoteSchema] normalizeNode: failed to parse JSON string for id=$id error=$e', name: 'YjsNoteSchema');
    }
  }

  static void _promoteTaskFields(YMap nodeMap, Map<String, dynamic> data) {
    final completed = nodeMap.get(fieldCompleted);
    if (completed is bool) data['completed'] = completed;

    final dueDate = nodeMap.get(fieldDueDate);
    if (dueDate is String) data['dueDate'] = dueDate;

    final recurrence = nodeMap.get(fieldRecurrence);
    if (recurrence is String) data['recurrence'] = recurrence;

    final lastCompletedAt = nodeMap.get(fieldLastCompletedAt);
    if (lastCompletedAt is String) data['lastCompletedAt'] = lastCompletedAt;

    final hasTime = nodeMap.get(fieldHasTime);
    if (hasTime is bool) data['hasTime'] = hasTime;

    final reminder = nodeMap.get(fieldReminder);
    if (reminder is String) data['reminder'] = reminder;
  }

  /// Canonical YText reader — single rule for the entire codebase.
  ///
  /// Priority: `content/$id` (canonical) → `content_fixed/$id` (legacy) →
  /// `nodeData['text']` (inline) → empty string.
  ///
  /// Every caller MUST use this method instead of rolling its own copy.
  static String readNodeTextContent(
    Doc doc,
    String nodeId, {
    Map<String, dynamic>? nodeData,
  }) {
    final contentKey = 'content/$nodeId';
    if (doc.share.containsKey(contentKey)) {
      try {
        final ytext = doc.getText(contentKey);
        if (ytext != null) {
          final text = ytext.toString();
          if (text.isNotEmpty) return text;
        }
      } catch (_) {}
    }

    final fixedKey = 'content_fixed/$nodeId';
    if (doc.share.containsKey(fixedKey)) {
      try {
        final ytext = doc.getText(fixedKey);
        if (ytext != null) {
          final text = ytext.toString();
          if (text.isNotEmpty) return text;
        }
      } catch (_) {}
    }

    final dataText = nodeData?['text'] as String?;
    if (dataText != null && dataText.isNotEmpty) return dataText;

    return '';
  }

  static void _writeNodeTextContent(Doc doc, String id, String text) {
    try {
      final sharedType = doc.getText('content/$id');
      if (sharedType != null) {
        _updateYTextIncrementally(sharedType, text);
        return;
      }
    } catch (e) {
      dev.log('[YjsNoteSchema] _writeNodeTextContent: content/$id failed, trying fallback', name: 'YjsNoteSchema', error: e);
    }

    try {
      final fallbackType = doc.getText('content_fixed/$id');
      if (fallbackType != null) {
        _updateYTextIncrementally(fallbackType, text);
      }
    } catch (e) {
      dev.log('[YjsNoteSchema] _writeNodeTextContent: fallback content_fixed/$id failed', name: 'YjsNoteSchema', error: e);
    }
  }

  static void _updateYTextIncrementally(YText ytext, String newText) {
    final oldText = ytext.toString();
    if (oldText == newText) return;

    int start = 0;
    int oldEnd = oldText.length;
    int newEnd = newText.length;

    while (start < oldEnd && start < newEnd && oldText.codeUnitAt(start) == newText.codeUnitAt(start)) {
      start++;
    }

    while (oldEnd > start && newEnd > start && oldText.codeUnitAt(oldEnd - 1) == newText.codeUnitAt(newEnd - 1)) {
      oldEnd--;
      newEnd--;
    }

    final deleteLen = oldEnd - start;
    if (deleteLen > 0) {
      ytext.delete(start, deleteLen);
    }

    if (newEnd > start) {
      final insertText = newText.substring(start, newEnd);
      ytext.insert(start, insertText);
    }
  }

  static num? _readCreatedAt(dynamic raw) {
    if (raw is YMap) {
      final val = raw.get(fieldCreatedAt);
      if (val is num) return val;
    }
    return null;
  }

  static String? _readParentId(dynamic raw) {
    if (raw is YMap) {
      final val = raw.get(fieldParentId);
      if (val is String) return val;
    }
    return null;
  }
}

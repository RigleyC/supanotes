import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:supanotes/core/utils/fractional_indexing.dart';
import 'package:super_editor/super_editor.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'editor_document_sync_manager.dart';
import 'node_codec.dart';
import 'yjs_node_codec.dart';
import 'yjs_task_entry.dart';

/// Wires a [Doc] to a [MutableDocument] via [EditorDocumentSyncManager].
///
/// Observes YMap("nodes") and YMap("tasks") for remote changes and applies
/// them to the editor document through the coordinator. The widget layer
/// observes the document (TaskNode.isComplete, etc.) — NOT the YMap directly.
/// This indirection is intentional: the bridge is the sole mediator of
/// YMap→document sync, keeping widget rendering decoupled from CRDT internals.
///
/// For local→remote: [EditorDocumentSyncManager] flush callbacks trigger YDoc mutations
/// which are then sent via [sendUpdate] (WS or REST).
class YjsDocEditorBridge {
  YjsDocEditorBridge({
    required Doc doc,
    required EditorDocumentSyncManager coordinator,
    required void Function(Uint8List update) sendUpdate,
    void Function()? onDocChanged,
  })  : _doc = doc,
        _coordinator = coordinator,
        _sendUpdate = sendUpdate,
        _onDocChanged = onDocChanged {
    final nodesMap = doc.getMap<Object>('nodes')!;
    final tasksMap = doc.getMap<String>('tasks')!;
    _onNodesChangedHandler = nodesMap.observe((e, _) {
      _onNodesChanged(_extractKeys(e));
    });
    _onTasksChangedHandler = tasksMap.observe((e, _) {
      _onTasksChanged(_extractKeys(e));
    });
    coordinator.onNodeFlush = onLocalFlush;
    // Apply initial YDoc state (observer only fires on changes).
    _onNodesChanged(null);
    _onTasksChanged(null);
  }

  final Doc _doc;
  final EditorDocumentSyncManager _coordinator;
  final void Function(Uint8List update) _sendUpdate;
  final void Function()? _onDocChanged;
  late final void Function(dynamic, Transaction) _onNodesChangedHandler;
  late final void Function(dynamic, Transaction) _onTasksChangedHandler;


  // Re-entrancy guard: prevents YMap observation during local flush.
  // Without this, onLocalFlush → YDoc mutation → onNodesChanged → coordinator
  // would try to re-apply the same nodes we just serialized.
  bool _isFlushingLocal = false;

  void _onNodesChanged(Set<String>? changedKeys) {
    if (_isFlushingLocal) {
      dev.log('[YjsBridge] _onNodesChanged: SKIP (local flush)', name: 'YjsBridge');
      return;
    }
    final sw = Stopwatch()..start();
    final nodes = noteNodesFromDoc(_doc);
    if (nodes.isNotEmpty) {
      _coordinator.updateNodesIncrementally(nodes);
    }
    _onDocChanged?.call();
    dev.log('[YjsBridge] _onNodesChanged: apply ${nodes.length} nodes elapsed=${sw.elapsedMilliseconds}ms', name: 'YjsBridge');
  }

  void _onTasksChanged(Set<String>? changedKeys) {
    if (_isFlushingLocal) return;

    final tasksMap = _doc.getMap<String>('tasks')!;
    final keys = changedKeys ?? tasksMap.keys.toList();
    final taskStates = <String, bool>{};

    for (final key in keys) {
      final entry = YjsTaskEntry.decode(tasksMap.get(key));
      if (entry != null) {
        taskStates[key] = entry.completed;
      }
    }

    if (taskStates.isNotEmpty) {
      _coordinator.syncTaskStates(taskStates);
      _onDocChanged?.call();
    }
  }

  /// Called by [EditorDocumentSyncManager] when local edits are flushed to SQLite.
  void onLocalFlush(List<NodeOperation> ops) {
    if (ops.isEmpty) return;
    final sw = Stopwatch()..start();
    dev.log('[YjsBridge] onLocalFlush START ops=${ops.length}', name: 'YjsBridge');

    _isFlushingLocal = true;
    try {
      _doc.transact((txn) {
        final nodesMap = _doc.getMap<Object>('nodes')!;

        for (final op in ops) {
          switch (op) {
            case InsertOp(:final id, :final node, :final index):
              final pos = _calcPosition(index, id, nodesMap);
              _serializeNode(node, pos, id, nodesMap);
            case DeleteOp(:final id):
              nodesMap.delete(id);
            case UpdateOp(:final id, :final node):
              _serializeNode(node, null, id, nodesMap);
            case MoveOp(:final id, :final to):
              final pos = _calcPosition(to, id, nodesMap);
              _repositionNode(id, pos, nodesMap);
          }
        }
      });

      final update = encodeStateAsUpdate(_doc);
      dev.log('[YjsBridge] onLocalFlush: sending update updateLen=${update.length} elapsed=${sw.elapsedMilliseconds}ms', name: 'YjsBridge');
      _sendUpdate(update);
    } finally {
      _isFlushingLocal = false;
    }
    _onDocChanged?.call();
    dev.log('[YjsBridge] onLocalFlush DONE elapsed=${sw.elapsedMilliseconds}ms', name: 'YjsBridge');
  }

  void _serializeNode(
    DocumentNode node,
    String? position,
    String id,
    YMap<Object> nodesMap,
  ) {
    final dataStr = NodeCodec.nodeData(node);
    final data = jsonDecode(dataStr) as Map<String, dynamic>;

    if (position == null) {
      final existing = _readPosition(id, nodesMap);
      position = existing ?? 'a0';
    }

    final existingRaw = nodesMap.get(id);
    final createdAt = _readCreatedAt(existingRaw) ??
        DateTime.now().millisecondsSinceEpoch.toDouble();
    final parentId = _readParentId(existingRaw) ?? '';

    // For task nodes, store completed in data
    if (node is TaskNode) {
      data['completed'] = node.isComplete;
    }

    final meta = <String, dynamic>{
      'id': id,
      'parentId': parentId,
      'position': position,
      'type': _attributionFor(node),
      'data': data,
      'createdAt': createdAt,
    };

      nodesMap.set(id, jsonEncode(meta));

    // P4 schema: write task state to YMap("tasks") as well
    if (node is TaskNode) {
      _setTaskField(id, node.isComplete, data['text'] as String? ?? '');
    }

    final text = data['text'] as String?;
    final ytext = _doc.getText('content/$id')!;
    _updateYTextIncrementally(ytext, text ?? '');
    dev.log('[YjsBridge] _serializeNode: id=$id type=${_attributionFor(node)} position=$position textLen=${text?.length ?? 0}', name: 'YjsBridge');
  }

  void _updateYTextIncrementally(YText ytext, String newText) {
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

  String _calcPosition(int targetIndex, String? ignoreId, YMap<Object> nodesMap) {
    final positions = <String, String>{};
    for (final key in nodesMap.keys) {
      if (key == ignoreId) continue;
      final raw = nodesMap.get(key);
      if (raw != null) {
        try {
          final meta = jsonDecode(raw as String) as Map<String, dynamic>;
          final pos = meta['position']?.toString() ?? '';
          positions[key] = pos;
        } catch (e, st) {
          dev.log('[YjsBridge] _calcPosition: JSON decode error', name: 'YjsBridge', error: e, stackTrace: st);
        }
      }
    }

    final sortedKeys = positions.keys.toList()
      ..sort((a, b) => positions[a]!.compareTo(positions[b]!));

    final prevKey = targetIndex > 0 && targetIndex - 1 < sortedKeys.length
        ? sortedKeys[targetIndex - 1]
        : null;
    final nextKey = targetIndex >= 0 && targetIndex < sortedKeys.length
        ? sortedKeys[targetIndex]
        : null;

    final prevPos = prevKey != null ? positions[prevKey] : null;
    final nextPos = nextKey != null ? positions[nextKey] : null;

    return FractionalIndex.between(prevPos, nextPos);
  }

  num? _readCreatedAt(dynamic raw) {
    if (raw is! String) return null;
    try {
      final meta = jsonDecode(raw) as Map<String, dynamic>;
      return meta['createdAt'] as num?;
    } catch (e, st) {
      dev.log('[YjsBridge] _readCreatedAt error', name: 'YjsBridge', error: e, stackTrace: st);
      return null;
    }
  }

  String? _readParentId(dynamic raw) {
    if (raw is! String) return null;
    try {
      final meta = jsonDecode(raw) as Map<String, dynamic>;
      return meta['parentId'] as String?;
    } catch (e, st) {
      dev.log('[YjsBridge] _readParentId error', name: 'YjsBridge', error: e, stackTrace: st);
      return null;
    }
  }

  void completeRecurringTask(String nodeId, DateTime nextDue) {
      _doc.transact((txn) {
      final nodesMap = _doc.getMap<Object>('nodes')!;
      final raw = nodesMap.get(nodeId);
      if (raw == null) return;
      try {
        final meta = jsonDecode(raw as String) as Map<String, dynamic>;
        if (meta['data'] is Map) {
          final data = Map<String, dynamic>.from(meta['data'] as Map);
          data['completed'] = false;
          data['dueDate'] = _formatDueDate(nextDue);
          data['lastCompletedAt'] = DateTime.now().toUtc().toIso8601String();
          meta['data'] = data;
          nodesMap.set(nodeId, jsonEncode(meta));

          final tasksMap = _doc.getMap<String>('tasks')!;
          final existingEntry = YjsTaskEntry.decode(tasksMap.get(nodeId));
          tasksMap.set(
            nodeId,
            YjsTaskEntry(
              nodeId: nodeId,
              completed: false,
              dueDate: _formatDueDate(nextDue),
              recurrence: existingEntry?.recurrence ?? data['recurrence'] as String?,
              lastCompletedAt: DateTime.now().toUtc().toIso8601String(),
              title: data['text'] as String? ?? '',
            ).encode(),
          );
        }
      } catch (e) {
        dev.log('[YjsBridge] Failed to complete recurring task', name: 'YjsBridge', error: e);
      }
    });
    final update = encodeStateAsUpdate(_doc);
    _sendUpdate(update);
    _onDocChanged?.call();
  }

  void updateTaskMetadataInYDoc(
    String nodeId, {
    DateTime? dueDate,
    String? recurrence,
    bool clearDueDate = false,
    bool clearRecurrence = false,
  }) {
    _doc.transact((txn) {
      final tasksMap = _doc.getMap<String>('tasks')!;
      final existing = YjsTaskEntry.decode(tasksMap.get(nodeId));
      if (existing == null) return;

      tasksMap.set(
        nodeId,
        existing.copyWith(
          dueDate: clearDueDate ? null : (dueDate != null ? _formatDueDate(dueDate) : existing.dueDate),
          recurrence: clearRecurrence ? null : (recurrence ?? existing.recurrence),
        ).encode(),
      );
    });

    final update = encodeStateAsUpdate(_doc);
    _sendUpdate(update);
    _onDocChanged?.call();
  }

  void _setTaskField(String nodeId, bool completed, String title) {
    final tasksMap = _doc.getMap<String>('tasks')!;
    final existing = YjsTaskEntry.decode(tasksMap.get(nodeId));
    tasksMap.set(
      nodeId,
      (existing ?? YjsTaskEntry(nodeId: nodeId, completed: completed, title: title)).copyWith(
        completed: completed,
        title: title,
      ).encode(),
    );
  }

  void _repositionNode(String id, String position, YMap<Object> nodesMap) {
    final raw = nodesMap.get(id);
    if (raw == null) return;
    try {
      final meta = jsonDecode(raw as String) as Map<String, dynamic>;
      meta['position'] = position;
    nodesMap.set(id, jsonEncode(meta));
    } catch (e, st) {
      dev.log('[YjsBridge] _repositionNode: JSON decode error', name: 'YjsBridge', error: e, stackTrace: st);
    }
  }

  String? _readPosition(String id, YMap<Object> nodesMap) {
    final raw = nodesMap.get(id);
    if (raw == null) return null;
    try {
      final meta = jsonDecode(raw as String) as Map<String, dynamic>;
      return meta['position']?.toString();
    } catch (e, st) {
      dev.log('[YjsBridge] _readPosition error', name: 'YjsBridge', error: e, stackTrace: st);
      return null;
    }
  }

  String _formatDueDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _attributionFor(DocumentNode node) {
    return NodeCodec.nodeType(node) ?? 'paragraph';
  }

  Set<String>? _extractKeys(dynamic event) {
    if (event is YEvent) {
      return event.keysChanged.isNotEmpty ? event.keysChanged : null;
    }
    return null;
  }

  void dispose() {
    final nodesMap = _doc.getMap<Object>('nodes');
    nodesMap?.unobserve(_onNodesChangedHandler);
    final tasksMap = _doc.getMap<String>('tasks');
    tasksMap?.unobserve(_onTasksChangedHandler);
    _coordinator.onNodeFlush = null;
  }
}

import 'dart:convert';
import 'dart:developer' as dev;
import 'package:supanotes/core/utils/fractional_indexing.dart';
import 'package:supanotes/features/tasks/domain/task_completion_command.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:super_editor/super_editor.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'editor_document_sync_manager.dart';
import 'node_codec.dart';
import 'yjs_node_codec.dart';

/// Wires a [Doc] to a [MutableDocument] via [EditorDocumentSyncManager].
///
/// Observes YMap("nodes") for remote changes and applies them to the
/// editor document through the coordinator. Each node is stored as a
/// nested [YMap] inside the nodes map, avoiding JSON blobs.
///
/// Local mutations are written directly to the YDoc. The sync layer
/// (SyncService polling) captures state changes independently.
class YjsDocEditorBridge {
  YjsDocEditorBridge({
    required Doc doc,
    required String userId,
    required EditorDocumentSyncManager coordinator,
    void Function()? onDocChanged,
  })  : _doc = doc,
        _userId = userId,
        _coordinator = coordinator,
        _onDocChanged = onDocChanged {
    final nodesMap = doc.getMap<Object>('nodes')!;
    _onNodesChangedHandler = nodesMap.observe((e, _) {
      _onNodesChanged(_extractKeys(e));
    });
    _onAfterTransactionHandler = (tr, d) {
      _onNodesChanged(null);
    };
    _doc.on('afterTransaction', _onAfterTransactionHandler);
    coordinator.onNodeFlush = onLocalFlush;
    // Apply initial YDoc state (observer only fires on changes).
    _onNodesChanged(null);
  }

  final Doc _doc;
  final String _userId;
  final EditorDocumentSyncManager _coordinator;
  final void Function()? _onDocChanged;
  late final void Function(dynamic, Transaction) _onNodesChangedHandler;
  late final void Function(Transaction, Doc) _onAfterTransactionHandler;

  // Re-entrancy guard: prevents YMap observation during local flush.
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
            case InsertOp(:final id, :final node, :final prevNodeId, :final nextNodeId):
              final pos = _calcPosition(prevNodeId, nextNodeId, id, nodesMap);
              _serializeNode(node, pos, id, nodesMap);
            case DeleteOp(:final id):
              nodesMap.delete(id);
            case UpdateOp(:final id, :final node):
              _serializeNode(node, null, id, nodesMap);
            case MoveOp(:final id, :final prevNodeId, :final nextNodeId):
              final pos = _calcPosition(prevNodeId, nextNodeId, id, nodesMap);
              _repositionNode(id, pos, nodesMap);
          }
        }
      });
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
    final data = NodeCodec.nodeData(node);

    if (position == null) {
      final existing = _readPosition(id, nodesMap);
      position = existing ?? 'a0';
    }

    final existingRaw = nodesMap.get(id);
    final createdAt = _readCreatedAt(existingRaw) ??
        DateTime.now().millisecondsSinceEpoch.toDouble();
    final parentId = _readParentId(existingRaw) ?? '';

    // nodesMap.get() returns YMap<dynamic>, not YMap<Object>.
    // Dart generics are invariant at runtime, so `as YMap<Object>` throws.
    // Use an untyped YMap variable to avoid the cast.
    // ignore: prefer_typing_uninitialized_variables
    YMap nodeMap;
    if (existingRaw is YMap) {
      // Reuse the existing YMap in-place to preserve CRDT identity.
      nodeMap = existingRaw;
    } else {
      nodeMap = YMap<Object>();
      nodesMap.set(id, nodeMap);
    }

    nodeMap.set('id', id);
    nodeMap.set('parentId', parentId);
    nodeMap.set('position', position);
    nodeMap.set('type', _attributionFor(node));
    nodeMap.set('data', jsonEncode(data));
    nodeMap.set('createdAt', createdAt);

    // For task nodes, write task fields to composite keys
    if (node is TaskNode) {
      nodesMap.set('$id:completed', node.isComplete);
    }

    String text = '';
    if (node is TextNode) {
      text = node.text.toPlainText();
    }
    _writeNodeTextContent(id, text);
    dev.log('[YjsBridge] _serializeNode: id=$id type=${_attributionFor(node)} position=$position textLen=${text.length}', name: 'YjsBridge');
  }

  void _writeNodeTextContent(String id, String text) {
    try {
      final sharedType = _doc.getText('content/$id');
      if (sharedType != null) {
        _updateYTextIncrementally(sharedType, text);
        return;
      }
    } catch (e) {
      dev.log('[YjsBridge] _serializeNode: content/$id is corrupted, falling back to content_fixed/$id', name: 'YjsBridge', error: e);
    }

    try {
      final fallbackType = _doc.getText('content_fixed/$id');
      if (fallbackType != null) {
        _updateYTextIncrementally(fallbackType, text);
      }
    } catch (e) {
      dev.log('[YjsBridge] _serializeNode: failed to write fallback content for $id', name: 'YjsBridge', error: e);
    }
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

  String _calcPosition(String? prevNodeId, String? nextNodeId, String? ignoreId, YMap<Object> nodesMap) {
    String? prevPos;
    String? nextPos;

    if (prevNodeId != null) {
      prevPos = _readPosition(prevNodeId, nodesMap);
    }
    if (nextNodeId != null) {
      nextPos = _readPosition(nextNodeId, nodesMap);
    }

    return FractionalIndex.between(prevPos, nextPos, _userId);
  }

  num? _readCreatedAt(dynamic raw) {
    if (raw is YMap) {
      final val = raw.get('createdAt');
      if (val is num) return val;
    }
    return null;
  }

  String? _readParentId(dynamic raw) {
    if (raw is YMap) {
      final val = raw.get('parentId');
      if (val is String) return val;
    }
    return null;
  }

  YMap _requireTaskNode(String nodeId) {
    final nodesMap = _doc.getMap<Object>('nodes')!;
    final raw = nodesMap.get(nodeId);
    if (raw is! YMap) {
      throw StateError('Task node $nodeId not found in YDoc');
    }
    return raw;
  }

  TaskSnapshot _readTaskSnapshot(String nodeId, YMap nodeMap) {
    final dueDateStr = nodeMap.get('dueDate') as String?;
    final hasTime = nodeMap.get('hasTime') as bool? ?? false;
    final recurrenceStr = nodeMap.get('recurrence') as String?;
    return TaskSnapshot(
      dueDate: dueDateStr != null ? DateTime.parse(dueDateStr) : null,
      hasTime: hasTime,
      recurrence: TaskRecurrence.parse(recurrenceStr),
    );
  }

  TaskCompletionResult completeTaskInYDoc(String nodeId, {DateTime? now}) {
    final nodeMap = _requireTaskNode(nodeId);
    final snapshot = _readTaskSnapshot(nodeId, nodeMap);
    final result = TaskCompletionCommand(() => now ?? DateTime.now()).complete(snapshot);

    _doc.transact((txn) {
      nodeMap.set('completed', result.completed);
      nodeMap.set('lastCompletedAt', result.completedAt.toIso8601String());
      if (result.nextDue == null) {
        nodeMap.delete('dueDate');
      } else {
        nodeMap.set('dueDate', _formatDueDate(result.nextDue!, hasTime: result.previousHasTime));
      }
    });

    _onDocChanged?.call();
    return result;
  }

  void reopenTaskInYDoc(String nodeId, {DateTime? previousDue}) {
    final nodeMap = _requireTaskNode(nodeId);
    _doc.transact((txn) {
      nodeMap.set('completed', false);
      nodeMap.delete('lastCompletedAt');
      if (previousDue != null) {
        nodeMap.set('dueDate', _formatDueDate(previousDue));
      }
    });

    _onDocChanged?.call();
  }

  void updateTaskMetadataInYDoc(
    String nodeId, {
    DateTime? dueDate,
    String? recurrence,
    bool clearDueDate = false,
    bool clearRecurrence = false,
    bool? hasTime,
    String? reminder,
    bool clearReminder = false,
  }) {
    _doc.transact((txn) {
      final nodesMap = _doc.getMap<Object>('nodes')!;
      final raw = nodesMap.get(nodeId);
      if (raw == null || raw is! YMap) return;

      if (clearDueDate) {
        nodesMap.delete('$nodeId:dueDate');
        nodesMap.delete('$nodeId:hasTime');
      } else if (dueDate != null) {
        nodesMap.set('$nodeId:dueDate', _formatDueDate(dueDate, hasTime: hasTime ?? false));
        if (hasTime != null) {
          nodesMap.set('$nodeId:hasTime', hasTime);
        }
      }

      if (clearRecurrence) {
        nodesMap.delete('$nodeId:recurrence');
      } else if (recurrence != null) {
        nodesMap.set('$nodeId:recurrence', recurrence);
      }

      if (clearReminder) {
        nodesMap.delete('$nodeId:reminder');
      } else if (reminder != null) {
        nodesMap.set('$nodeId:reminder', reminder);
      }
    });

    _onDocChanged?.call();
  }

  void _repositionNode(String id, String position, YMap<Object> nodesMap) {
    final raw = nodesMap.get(id);
    if (raw == null) return;
    if (raw is! YMap) return;
    raw.set('position', position);
  }

  String? _readPosition(String id, YMap<Object> nodesMap) {
    final raw = nodesMap.get(id);
    if (raw is YMap) {
      final val = raw.get('position');
      if (val is String) return val;
    }
    return null;
  }

  String _formatDueDate(DateTime date, {bool hasTime = false}) {
    if (hasTime) {
      final h = date.hour.toString().padLeft(2, '0');
      final m = date.minute.toString().padLeft(2, '0');
      return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}T$h:$m';
    }
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
    _doc.off('afterTransaction', _onAfterTransactionHandler);
    _coordinator.onNodeFlush = null;
  }
}

import 'dart:async';
import 'dart:developer' as dev;
import 'dart:typed_data';
import 'package:supanotes/core/utils/fractional_indexing.dart';
import 'package:supanotes/features/tasks/domain/task_completion_command.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:super_editor/super_editor.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'editor_document_sync_manager.dart';
import 'note_node.dart';
import 'yjs_note_schema.dart';
import 'yjs_node_codec.dart';

/// Wires a [Doc] to a [MutableDocument] via [EditorDocumentSyncManager].
///
/// Observes YMap("nodes") for remote changes and applies them to the
/// editor document through the coordinator. Each node is stored as a
/// nested [YMap] inside the nodes map, avoiding JSON blobs.
///
/// Local mutations are written directly to the YDoc. The sync layer
/// (SyncService polling) captures state changes independently.
///
/// Remote changes are coalesced via [scheduleMicrotask] to batch multiple
/// observer callbacks from the same transaction.
class YjsDocEditorBridge {
  YjsDocEditorBridge({
    required Doc doc,
    required String userId,
    required EditorDocumentSyncManager coordinator,
    void Function({required bool isRemote})? onDocChanged,
    void Function(Uint8List)? sendUpdate,
    void Function(Set<String> nodeIds)? onDocCommitted,
  })  : _doc = doc,
        _userId = userId,
        _coordinator = coordinator,
        _onDocChanged = onDocChanged,
        _sendUpdate = sendUpdate,
        _onDocCommitted = onDocCommitted {
    final nodesMap = doc.getMap<Object>('nodes')!;
    _onNodesChangedHandler = nodesMap.observe((e, _) {
      if (_isFlushingLocal) return;
      if (e.keysChanged.isNotEmpty) {
        _scheduleRemoteApply(e.keysChanged.cast<String>());
      }
    });
    _onAfterTransactionHandler = (Transaction tr, Doc d) {
      if (_isFlushingLocal) return;
      _onAfterTransaction(tr, d);
    };
    _doc.on('afterTransaction', _onAfterTransactionHandler);

    coordinator.onNodeFlush = onLocalFlush;

    // Apply initial YDoc state (observer only fires on changes).
    final initialIds = Set<String>.from(nodesMap.keys.where(
      (k) => !k.contains(':'),
    ));
    if (initialIds.isNotEmpty) {
      _scheduleRemoteApply(initialIds);
    }
  }

  final Doc _doc;
  final String _userId;
  final EditorDocumentSyncManager _coordinator;
  final void Function({required bool isRemote})? _onDocChanged;
  final void Function(Uint8List)? _sendUpdate;
  final void Function(Set<String> nodeIds)? _onDocCommitted;
  late final void Function(dynamic, Transaction) _onNodesChangedHandler;
  late final void Function(Transaction, Doc) _onAfterTransactionHandler;

  bool _isFlushingLocal = false;

  // ---------------------------------------------------------------------------
  // Coalesced remote-apply batching
  // ---------------------------------------------------------------------------

  final Set<String> _pendingRemoteIds = {};
  bool _remoteApplyQueued = false;

  void _scheduleRemoteApply(Set<String> changedIds) {
    _pendingRemoteIds.addAll(changedIds);
    if (_remoteApplyQueued) return;
    _remoteApplyQueued = true;
    scheduleMicrotask(() {
      _remoteApplyQueued = false;
      final ids = {..._pendingRemoteIds};
      _pendingRemoteIds.clear();
      _applyChangedNodes(ids);
    });
  }

  void _applyChangedNodes(Set<String> ids) {
    if (_isFlushingLocal || ids.isEmpty) return;
    final sw = Stopwatch()..start();
    final nodes = <NoteNode>[];
    for (final id in ids) {
      // Skip composite keys
      if (id.contains(':')) continue;
      final node = noteNodeFromYDoc(_doc, id);
      if (node != null) nodes.add(node);
    }
    if (nodes.isNotEmpty) {
      nodes.sort((a, b) => a.position.compareTo(b.position));
      _coordinator.updateNodesIncrementally(nodes);
    }
    _onDocChanged?.call(isRemote: true);
    dev.log('[YjsBridge] _applyChangedNodes: apply ${nodes.length} nodes elapsed=${sw.elapsedMilliseconds}ms', name: 'YjsBridge');
  }

  void _onAfterTransaction(Transaction tr, Doc d) {
    final changedIds = <String>{};
    for (final type in tr.changed.keys) {
      if (type is YText) {
        final nodeId = _extractNodeIdFromYText(type);
        if (nodeId != null) {
          changedIds.add(nodeId);
        }
      }
    }
    if (changedIds.isNotEmpty) {
      _scheduleRemoteApply(changedIds);
    }
  }

  String? _extractNodeIdFromYText(YText ytext) {
    for (final entry in _doc.share.entries) {
      if (entry.value == ytext) {
        const prefix = 'content/';
        const fixedPrefix = 'content_fixed/';
        if (entry.key.startsWith(prefix)) {
          return entry.key.substring(prefix.length);
        }
        if (entry.key.startsWith(fixedPrefix)) {
          return entry.key.substring(fixedPrefix.length);
        }
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Local flush
  // ---------------------------------------------------------------------------

  void onLocalFlush(List<NodeOperation> ops) {
    if (ops.isEmpty) return;
    final sw = Stopwatch()..start();
    dev.log('[YjsBridge] onLocalFlush START ops=${ops.length}', name: 'YjsBridge');

    final changedIds = <String>{};

    _isFlushingLocal = true;
    try {
      _doc.transact((txn) {
        final nodesMap = _doc.getMap<Object>('nodes')!;

        for (final op in ops) {
          switch (op) {
            case InsertOp(:final id, :final node, :final prevNodeId, :final nextNodeId):
              final pos = _calcPosition(prevNodeId, nextNodeId, id, nodesMap);
              _writeCanonicalNode(node, pos, id, nodesMap);
              changedIds.add(id);
            case DeleteOp(:final id):
              nodesMap.delete(id);
              changedIds.add(id);
            case UpdateOp(:final id, :final node):
              _writeCanonicalNode(node, null, id, nodesMap);
              changedIds.add(id);
            case MoveOp(:final id, :final prevNodeId, :final nextNodeId):
              final pos = _calcPosition(prevNodeId, nextNodeId, id, nodesMap);
              _repositionNode(id, pos, nodesMap);
              changedIds.add(id);
          }
        }
      });
    } finally {
      _isFlushingLocal = false;
    }

    _onDocChanged?.call(isRemote: false);
    _onDocCommitted?.call(changedIds);

    if (_sendUpdate != null) {
      final updateBytes = encodeStateAsUpdate(_doc);
      _sendUpdate(updateBytes);
    }

    dev.log('[YjsBridge] onLocalFlush DONE elapsed=${sw.elapsedMilliseconds}ms', name: 'YjsBridge');
  }

  void _writeCanonicalNode(
    DocumentNode node,
    String? position,
    String id,
    YMap<Object> nodesMap,
  ) {
    if (position == null) {
      final existing = _readPosition(id, nodesMap);
      position = existing ?? 'a0';
    }

    YjsNoteSchema.writeNode(_doc, node, position: position);
  }

  // ---------------------------------------------------------------------------
  // Task operations (canonical — fields inside node YMap)
  // ---------------------------------------------------------------------------

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

    _onDocChanged?.call(isRemote: false);
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

    _onDocChanged?.call(isRemote: false);
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
    dev.log(
      '[Bridge] updateTaskMetadataInYDoc: nodeId=$nodeId dueDate=$dueDate clearDueDate=$clearDueDate recurrence=$recurrence clearRecurrence=$clearRecurrence hasTime=$hasTime reminder=$reminder clearReminder=$clearReminder',
      name: 'YjsBridge',
    );
    _doc.transact((txn) {
      final nodesMap = _doc.getMap<Object>('nodes')!;
      final raw = nodesMap.get(nodeId);
      if (raw == null || raw is! YMap) return;

      if (clearDueDate) {
        raw.delete('dueDate');
        raw.delete('hasTime');
      } else if (dueDate != null) {
        raw.set('dueDate', _formatDueDate(dueDate, hasTime: hasTime ?? false));
        if (hasTime != null) {
          raw.set('hasTime', hasTime);
        }
      }

      if (clearRecurrence) {
        raw.delete('recurrence');
      } else if (recurrence != null) {
        raw.set('recurrence', recurrence);
      }

      if (clearReminder) {
        raw.delete('reminder');
      } else if (reminder != null) {
        raw.set('reminder', reminder);
      }
    });

    dev.log(
      '[Bridge] _onDocChanged called after updateTaskMetadataInYDoc',
      name: 'YjsBridge',
    );
    _onDocChanged?.call(isRemote: false);
    dev.log(
      '[Bridge] _onDocChanged done',
      name: 'YjsBridge',
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _repositionNode(String id, String position, YMap<Object> nodesMap) {
    final raw = nodesMap.get(id);
    if (raw == null || raw is! YMap) return;
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

  String _formatDueDate(DateTime date, {bool hasTime = false}) {
    if (hasTime) {
      final h = date.hour.toString().padLeft(2, '0');
      final m = date.minute.toString().padLeft(2, '0');
      return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}T$h:$m';
    }
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  void dispose() {
    final nodesMap = _doc.getMap<Object>('nodes');
    nodesMap?.unobserve(_onNodesChangedHandler);
    _doc.off('afterTransaction', _onAfterTransactionHandler);
    _coordinator.onNodeFlush = null;
  }
}

import 'dart:async';
import 'dart:developer' as dev;

import 'package:super_editor/super_editor.dart';

import 'node_codec.dart';
import 'note_node.dart';
import 'yjs_task_entry.dart';

sealed class NodeOperation {}

class InsertOp extends NodeOperation {
  final String id;
  final DocumentNode node;
  final int index;
  InsertOp(this.id, this.node, this.index);
}

class UpdateOp extends NodeOperation {
  final String id;
  final DocumentNode node;
  UpdateOp(this.id, this.node);
}

class MoveOp extends NodeOperation {
  final String id;
  final int from;
  final int to;
  MoveOp(this.id, this.from, this.to);
}

class DeleteOp extends NodeOperation {
  final String id;
  DeleteOp(this.id);
}

/// Coordinates remote-to-local sync and local dirty tracking for a single note.
///
/// Merges the former [NoteSyncCoordinator] (remote→local application) and
/// [NodeSyncManager] (local→remote dirty tracking & serialization) into one
/// class to eliminate delegation indirection.
class EditorDocumentSyncManager {
  EditorDocumentSyncManager({
    required MutableDocument document,
    required Editor editor,
    this.onNodeFlush,
  })  : _document = document,
        _editor = editor {
    _document.addListener(_onDocumentChanged);
  }

  final MutableDocument _document;
  final Editor _editor;
  void Function(List<NodeOperation> ops)? onNodeFlush;

  final List<NodeOperation> _pendingOps = [];
  Timer? _debounceTimer;

  final Set<String> locallyDirtyNodeIds = {};

  int _opSequence = 0;
  final Map<String, int> _dirtyNodeSequences = {};

  Future<void> _writeLock = Future.value();

  void _enqueueDbWrite(FutureOr<void> Function() action) {
    _writeLock = _writeLock.then((_) async {
      try {
        await action();
      } catch (e, stackTrace) {
        dev.log('SQLite write error: $e', name: 'EditorDocumentSyncManager', error: e, stackTrace: stackTrace, level: 1000);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Local document observation
  // ---------------------------------------------------------------------------

  void _onDocumentChanged(DocumentChangeLog changeLog) {
    _opSequence++;
    for (final change in changeLog.changes) {
      if (change is NodeInsertedEvent) {
        final node = _document.getNodeById(change.nodeId);
        if (node != null) {
          _pendingOps.add(InsertOp(change.nodeId, node, change.insertionIndex));
          locallyDirtyNodeIds.add(change.nodeId);
          _dirtyNodeSequences[change.nodeId] = _opSequence;
        }
      } else if (change is NodeRemovedEvent) {
        _pendingOps.add(DeleteOp(change.nodeId));
        locallyDirtyNodeIds.add(change.nodeId);
        _dirtyNodeSequences[change.nodeId] = _opSequence;
      } else if (change is NodeMovedEvent) {
        _pendingOps.add(MoveOp(change.nodeId, change.from, change.to));
        locallyDirtyNodeIds.add(change.nodeId);
        _dirtyNodeSequences[change.nodeId] = _opSequence;
      } else if (change is NodeChangeEvent) {
        final node = _document.getNodeById(change.nodeId);
        if (node != null) {
          _pendingOps.add(UpdateOp(change.nodeId, node));
          locallyDirtyNodeIds.add(change.nodeId);
          _dirtyNodeSequences[change.nodeId] = _opSequence;
        }
      }
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 50), () {
      _enqueueDbWrite(_drainQueue);
    });
  }

  Future<void> _drainQueue() async {
    if (_pendingOps.isEmpty) return;

    final opsToProcess = List<NodeOperation>.from(_pendingOps);
    _pendingOps.clear();
    final snapshotSeq = _opSequence;

    final flushedIds = opsToProcess.map(_opNodeId).whereType<String>().toSet();
    for (final id in flushedIds) {
      final seq = _dirtyNodeSequences[id];
      if (seq != null && seq <= snapshotSeq) {
        locallyDirtyNodeIds.remove(id);
        _dirtyNodeSequences.remove(id);
      }
    }

    if (opsToProcess.isNotEmpty) {
      onNodeFlush?.call(opsToProcess);
    }
  }

  Future<void> flushNow() {
    _debounceTimer?.cancel();
    if (_pendingOps.isEmpty) return _writeLock;

    final opsToProcess = List<NodeOperation>.from(_pendingOps);
    _pendingOps.clear();
    final snapshotSeq = _opSequence;

    _enqueueDbWrite(() async {
      final flushedIds = opsToProcess.map(_opNodeId).whereType<String>().toSet();
      for (final id in flushedIds) {
        final seq = _dirtyNodeSequences[id];
        if (seq != null && seq <= snapshotSeq) {
          locallyDirtyNodeIds.remove(id);
          _dirtyNodeSequences.remove(id);
        }
      }
    });

    if (opsToProcess.isNotEmpty) {
      onNodeFlush?.call(opsToProcess);
    }

    return _writeLock;
  }

  static String? _opNodeId(NodeOperation op) => switch (op) {
    InsertOp(:final id) => id,
    UpdateOp(:final id) => id,
    MoveOp(:final id) => id,
    DeleteOp(:final id) => id,
  };

  // ---------------------------------------------------------------------------
  // Remote-change application
  // ---------------------------------------------------------------------------

  void updateNodesIncrementally(List<NoteNode> incomingNodes) {
    _applyRemote(() => _applyIncomingNodes(incomingNodes));
  }

  void syncTaskStates(Map<String, bool> taskCompletionMap) {
    _applyRemote(() => _applyTaskCompletionStates(taskCompletionMap));
  }

  void _applyRemote(void Function() fn) {
    suspendSync();
    try {
      fn();
    } finally {
      resumeSync();
    }
  }

  void _applyIncomingNodes(List<NoteNode> incomingNodes) {
    if (incomingNodes.isEmpty) {
      return;
    }

    final dirtyIds = locallyDirtyNodeIds;
    final requests = <EditRequest>[];
    final incomingIds = incomingNodes.map((n) => n.id).toSet();
    final currentIds = _document.toList().map((n) => n.id).toList();

    // 1. Delete nodes that are not in incoming (and not dirty locally)
    for (int i = currentIds.length - 1; i >= 0; i--) {
      final id = currentIds[i];
      if (!incomingIds.contains(id)) {
        if (!dirtyIds.contains(id)) {
          requests.add(DeleteNodeRequest(nodeId: id));
          currentIds.removeAt(i);
        }
      }
    }

    // 2. Process incoming nodes in order
    for (int i = 0; i < incomingNodes.length; i++) {
      final incoming = incomingNodes[i];
      final existingNode = _document.getNodeById(incoming.id);
      
      // If it exists in the YDoc but is dirty locally, we keep local state (skip replacement).
      // However, its POSITION in YDoc might still be different from local document.
      // For now, if it's dirty locally, we also skip moving it, to avoid fighting the user's cursor.
      if (dirtyIds.contains(incoming.id)) continue;

      if (existingNode == null) {
        // Insert
        final newNode = NodeCodec.createNodeFromSchema(incoming);
        requests.add(InsertNodeAtIndexRequest(nodeIndex: i, newNode: newNode));
        currentIds.insert(i, incoming.id);
      } else {
        // Check position
        final oldIndex = currentIds.indexOf(incoming.id);
        if (oldIndex != i && oldIndex != -1) {
          requests.add(MoveNodeRequest(nodeId: incoming.id, newIndex: i));
          currentIds.removeAt(oldIndex);
          currentIds.insert(i, incoming.id);
        }

        // Check content changes
        if (existingNode is TaskNode && incoming.type == 'task') {
          try {
            final existingEntry = YjsTaskEntry.decode(NodeCodec.nodeData(existingNode));
            final incomingEntry = YjsTaskEntry.decode(incoming.data);

            if (existingEntry != null && incomingEntry != null && existingEntry == incomingEntry) {
              if (existingNode.isComplete != incomingEntry.completed) {
                requests.add(ChangeTaskCompletionRequest(
                  nodeId: incoming.id,
                  isComplete: incomingEntry.completed,
                ));
              }
              continue; // Content is equivalent, skip replacement
            }
          } catch (_) {}
        }

        if (NodeCodec.isNodeEquivalent(existingNode, incoming)) continue;
        
        final newNode = NodeCodec.createNodeFromSchema(incoming);
        requests.add(
          ReplaceNodeRequest(
            existingNodeId: incoming.id,
            newNode: newNode,
          ),
        );
      }
    }

    if (requests.isNotEmpty) {
      _editor.executePreservingSelection(requests);
    }
  }

  void _applyTaskCompletionStates(Map<String, bool> taskCompletionMap) {
    final requests = <EditRequest>[];
    for (final node in _document) {
      if (node is TaskNode) {
        final isDbCompleted = taskCompletionMap[node.id];
        if (isDbCompleted != null && node.isComplete != isDbCompleted) {
          requests.add(ChangeTaskCompletionRequest(
            nodeId: node.id,
            isComplete: isDbCompleted,
          ));
        }
      }
    }
    if (requests.isNotEmpty) {
      _editor.executePreservingSelection(requests);
    }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  void suspendSync() {
    _document.removeListener(_onDocumentChanged);
  }

  void resumeSync() {
    _document.addListener(_onDocumentChanged);
  }

  Future<void> dispose() async {
    await flushNow();
    _debounceTimer?.cancel();
    _document.removeListener(_onDocumentChanged);
  }
}

extension EditorSelectionPreservation on Editor {
  void executePreservingSelection(List<EditRequest> requests) {
    if (requests.isEmpty) return;

    final document = context.document;
    final composer = context.composer;
    final oldSelection = composer.selection;

    execute(requests);

    if (oldSelection != null) {
      final baseNodeExists = document.getNodeById(oldSelection.base.nodeId) != null;
      final extentNodeExists = document.getNodeById(oldSelection.extent.nodeId) != null;
      if (baseNodeExists && extentNodeExists) {
        final newBase = _clampPosition(document, oldSelection.base);
        final newExtent = _clampPosition(document, oldSelection.extent);
        final finalSelection = DocumentSelection(base: newBase, extent: newExtent);

        if (finalSelection != composer.selection) {
          execute([
            ChangeSelectionRequest(
              finalSelection,
              SelectionChangeType.placeCaret,
              SelectionReason.contentChange,
            ),
          ]);
        }
      }
    }
  }

  DocumentPosition _clampPosition(Document document, DocumentPosition pos) {
    final node = document.getNodeById(pos.nodeId);
    if (node is TextNode && pos.nodePosition is TextNodePosition) {
      final maxLen = node.text.toPlainText().length;
      final offset = (pos.nodePosition as TextNodePosition).offset;
      if (offset > maxLen) {
        return DocumentPosition(
          nodeId: pos.nodeId,
          nodePosition: TextNodePosition(offset: maxLen),
        );
      }
    }
    return pos;
  }
}

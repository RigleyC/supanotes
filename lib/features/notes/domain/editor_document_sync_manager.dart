import 'dart:async';
import 'dart:developer' as dev;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:super_editor/super_editor.dart';

import 'node_codec.dart';
import 'note_node.dart';

sealed class NodeOperation {}

class InsertOp extends NodeOperation {
  final String id;
  final DocumentNode node;
  final String? prevNodeId;
  final String? nextNodeId;
  InsertOp(this.id, this.node, this.prevNodeId, this.nextNodeId);
}

class UpdateOp extends NodeOperation {
  final String id;
  final DocumentNode node;
  UpdateOp(this.id, this.node);
}

class MoveOp extends NodeOperation {
  final String id;
  final String? prevNodeId;
  final String? nextNodeId;
  MoveOp(this.id, this.prevNodeId, this.nextNodeId);
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
  }) : _document = document,
       _editor = editor {
    _document.addListener(_onDocumentChanged);
  }

  final MutableDocument _document;
  final Editor _editor;
  void Function(List<NodeOperation> ops)? onNodeFlush;

  final Map<String, NodeOperation> _pendingOps = {};
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
        dev.log(
          'SQLite write error: $e',
          name: 'EditorDocumentSyncManager',
          error: e,
          stackTrace: stackTrace,
          level: 1000,
        );
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
          final currentIndex = _document.getNodeIndexById(change.nodeId);
          final prevNodeId = currentIndex > 0
              ? _document.getNodeAt(currentIndex - 1)?.id
              : null;
          final nextNodeId = currentIndex + 1 < _document.nodeCount
              ? _document.getNodeAt(currentIndex + 1)?.id
              : null;
          _pendingOps[change.nodeId] = InsertOp(
            change.nodeId,
            node,
            prevNodeId,
            nextNodeId,
          );
          locallyDirtyNodeIds.add(change.nodeId);
          _dirtyNodeSequences[change.nodeId] = _opSequence;
        }
      } else if (change is NodeRemovedEvent) {
        if (_pendingOps[change.nodeId] is InsertOp) {
          _pendingOps.remove(change.nodeId);
          locallyDirtyNodeIds.remove(change.nodeId);
          _dirtyNodeSequences.remove(change.nodeId);
        } else {
          _pendingOps[change.nodeId] = DeleteOp(change.nodeId);
          locallyDirtyNodeIds.add(change.nodeId);
          _dirtyNodeSequences[change.nodeId] = _opSequence;
        }
      } else if (change is NodeMovedEvent) {
        final currentIndex = _document.getNodeIndexById(change.nodeId);
        final prevNodeId = currentIndex > 0
            ? _document.getNodeAt(currentIndex - 1)?.id
            : null;
        final nextNodeId = currentIndex + 1 < _document.nodeCount
            ? _document.getNodeAt(currentIndex + 1)?.id
            : null;
        final existing = _pendingOps[change.nodeId];
        if (existing is InsertOp) {
          final node = _document.getNodeById(change.nodeId);
          if (node != null) {
            _pendingOps[change.nodeId] = InsertOp(
              change.nodeId,
              node,
              prevNodeId,
              nextNodeId,
            );
          }
        } else {
          _pendingOps[change.nodeId] = MoveOp(
            change.nodeId,
            prevNodeId,
            nextNodeId,
          );
        }
        locallyDirtyNodeIds.add(change.nodeId);
        _dirtyNodeSequences[change.nodeId] = _opSequence;
      } else if (change is NodeChangeEvent) {
        final node = _document.getNodeById(change.nodeId);
        if (node != null) {
          final existing = _pendingOps[change.nodeId];
          if (existing is InsertOp) {
            _pendingOps[change.nodeId] = InsertOp(
              change.nodeId,
              node,
              existing.prevNodeId,
              existing.nextNodeId,
            );
          } else {
            _pendingOps[change.nodeId] = UpdateOp(change.nodeId, node);
          }
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

    final opsToProcess = List<NodeOperation>.from(_pendingOps.values);
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

    final opsToProcess = List<NodeOperation>.from(_pendingOps.values);
    _pendingOps.clear();
    final snapshotSeq = _opSequence;

    _enqueueDbWrite(() async {
      final flushedIds = opsToProcess
          .map(_opNodeId)
          .whereType<String>()
          .toSet();
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

  void reconcileRemoteSnapshot(List<NoteNode> snapshot) {
    dev.log('[EditorSync] reconcileRemoteSnapshot START (snapshot size: ${snapshot.length})', name: 'EditorDocumentSyncManager');
    _applyIncomingNodes(snapshot);
    dev.log('[EditorSync] reconcileRemoteSnapshot END', name: 'EditorDocumentSyncManager');
  }

  void _applyIncomingNodes(List<NoteNode> snapshot) {
    dev.log('[EditorSync] _applyIncomingNodes START', name: 'EditorDocumentSyncManager');
    final currentIds = _document.toList().map((n) => n.id).toList();
    final incomingIds = snapshot.map((n) => n.id).toList();
    final incomingById = {for (final n in snapshot) n.id: n};
    final requests = <EditRequest>[];

    dev.log('[EditorSync] _applyIncomingNodes currentIds: ${currentIds.length}, incomingIds: ${incomingIds.length}', name: 'EditorDocumentSyncManager');

    // 1. Delete nodes that are not in incoming
    for (int i = currentIds.length - 1; i >= 0; i--) {
      final id = currentIds[i];
      if (!incomingIds.contains(id)) {
        dev.log('[EditorSync] Deleting node $id (not in incoming)', name: 'EditorDocumentSyncManager');
        requests.add(DeleteNodeRequest(nodeId: id));
        currentIds.removeAt(i);
      }
    }

    // 2. Process incoming nodes in order
    for (int i = 0; i < snapshot.length; i++) {
      final incoming = snapshot[i];
      final existingNode = _document.getNodeById(incoming.id);

      if (existingNode == null) {
        // Insert
        final newNode = NodeCodec.createNodeFromSchema(incoming);
        dev.log('[EditorSync] Inserting new node ${incoming.id} at index $i', name: 'EditorDocumentSyncManager');
        requests.add(InsertNodeAtIndexRequest(nodeIndex: i, newNode: newNode));
        currentIds.insert(i, incoming.id);
      } else {
        // Check position
        final oldIndex = currentIds.indexOf(incoming.id);
        if (oldIndex != i && oldIndex != -1) {
          dev.log('[EditorSync] Moving existing node ${incoming.id} from $oldIndex to $i', name: 'EditorDocumentSyncManager');
          requests.add(MoveNodeRequest(nodeId: incoming.id, newIndex: i));
          currentIds.removeAt(oldIndex);
          currentIds.insert(i, incoming.id);
        }

        // Check content changes
        if (existingNode is TaskNode && incoming.type == 'task') {
          try {
            final incomingData = incoming.data;
            final incomingCompleted = incomingData['completed'] == true;

            if (existingNode.isComplete != incomingCompleted) {
              requests.add(
                ChangeTaskCompletionRequest(
                  nodeId: incoming.id,
                  isComplete: incomingCompleted,
                ),
              );
            }

            // Check if only task state changed — skip full node replacement
            final existingData = NodeCodec.nodeData(existingNode);
            existingData['completed'] = incomingCompleted;
            if (NodeCodec.deepEquals(existingData, incoming.data)) continue;
          } catch (_) {}
        }

        if (NodeCodec.isNodeEquivalent(existingNode, incoming)) continue;

        final newNode = NodeCodec.createNodeFromSchema(incoming);
        dev.log('[EditorSync] Replacing node ${incoming.id} (content/type changed)', name: 'EditorDocumentSyncManager');
        requests.add(
          ReplaceNodeRequest(existingNodeId: incoming.id, newNode: newNode),
        );
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
    DocumentComposer? composer;
    try {
      composer = context.composer;
    } catch (_) {}
    final oldSelection = composer?.selection;

    dev.log(
      '[EditorSync] executePreservingSelection starting. Requests: ${requests.length}, oldSelection: $oldSelection',
      name: 'EditorDocumentSyncManager',
    );

    // Check if the current selection points to a node that will be deleted.
    bool selectionWillBeDeleted = false;
    if (oldSelection != null) {
      final deletedIds = requests
          .whereType<DeleteNodeRequest>()
          .map((req) => req.nodeId)
          .toSet();
      if (deletedIds.contains(oldSelection.base.nodeId) ||
          deletedIds.contains(oldSelection.extent.nodeId)) {
        selectionWillBeDeleted = true;
      }
      
      dev.log(
        '[EditorSync] deletedIds: $deletedIds, selectionWillBeDeleted: $selectionWillBeDeleted',
        name: 'EditorDocumentSyncManager',
      );
    }

    if (selectionWillBeDeleted) {
      dev.log('[EditorSync] Prepending clear selection request.', name: 'EditorDocumentSyncManager');
      requests.insert(
        0,
        const ChangeSelectionRequest(
          null,
          SelectionChangeType.clearSelection,
          SelectionReason.contentChange,
        ),
      );
    }

    try {
      execute(requests);
      dev.log('[EditorSync] Batch execute finished.', name: 'EditorDocumentSyncManager');
    } catch (e, st) {
      dev.log('[EditorSync] CRASH during execute!', error: e, stackTrace: st, name: 'EditorDocumentSyncManager');
      rethrow;
    }

    if (oldSelection != null && !selectionWillBeDeleted) {
      final baseNodeExists =
          document.getNodeById(oldSelection.base.nodeId) != null;
      final extentNodeExists =
          document.getNodeById(oldSelection.extent.nodeId) != null;
      
      dev.log(
        '[EditorSync] Restoring selection. baseExists: $baseNodeExists, extentExists: $extentNodeExists',
        name: 'EditorDocumentSyncManager',
      );

      if (baseNodeExists && extentNodeExists) {
        final newBase = _clampPosition(document, oldSelection.base);
        final newExtent = _clampPosition(document, oldSelection.extent);
        final finalSelection = DocumentSelection(
          base: newBase,
          extent: newExtent,
        );

        dev.log('[EditorSync] Restored clamped selection.', name: 'EditorDocumentSyncManager');
        execute([
          ChangeSelectionRequest(
            finalSelection,
            SelectionChangeType.placeCaret,
            SelectionReason.contentChange,
          ),
        ]);
      } else {
        dev.log('[EditorSync] Node was lost unexpectedly, falling back to clear selection.', name: 'EditorDocumentSyncManager');
        // Fallback in case a node was lost in a way other than DeleteNodeRequest
        execute([
          const ChangeSelectionRequest(
            null,
            SelectionChangeType.clearSelection,
            SelectionReason.contentChange,
          ),
        ]);
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

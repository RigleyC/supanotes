/// Coordinates remote-to-local sync for a single note document.
///
/// Owns a [NodeSyncManager] for local dirty tracking and serialization,
/// and applies incoming remote nodes / task states to the live
/// [MutableDocument] through the [Editor].
///
/// Synchronisation is suspended while incoming changes are being applied
/// to prevent the [NodeSyncManager] from overwriting remote data with
/// stale local snapshots.
library;

import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:super_editor/super_editor.dart';

import '../../../core/database/database.dart';
import 'node_sync_manager.dart';

class NoteSyncCoordinator {
  late final NodeSyncManager _nodeSyncManager;

  NoteSyncCoordinator({
    required AppDatabase database,
    required String noteId,
    required String userId,
    required MutableDocument document,
    required Editor editor,
  })  : _document = document,
        _editor = editor {
    _nodeSyncManager = NodeSyncManager(
      database: database,
      noteId: noteId,
      userId: userId,
      document: document,
    );
  }

  void Function(List<NodeOperation> ops)? get onNodeFlush =>
      _nodeSyncManager.onFlush;
  set onNodeFlush(void Function(List<NodeOperation> ops)? cb) {
    _nodeSyncManager.onFlush = cb;
  }

  final MutableDocument _document;
  final Editor _editor;

  Set<String> get locallyDirtyNodeIds =>
      _nodeSyncManager.locallyDirtyNodeIds;

  static MutableDocument documentFromNodes(List<NoteNode> nodes) =>
      NodeSyncManager.documentFromNodes(nodes);

  void updateNodesIncrementally(List<NoteNode> incomingNodes) {
    _applyRemote(() => _applyIncomingNodes(incomingNodes));
  }

  void syncTaskStates(Map<String, bool> taskCompletionMap) {
    _applyRemote(() => _applyTaskCompletionStates(taskCompletionMap));
  }

  void suspendSync() => _nodeSyncManager.suspendSync();

  void resumeSync() => _nodeSyncManager.resumeSync();

  Future<void> dispose() => _nodeSyncManager.dispose();

  // ---------------------------------------------------------------------------
  // Remote-change application
  // ---------------------------------------------------------------------------

  void _applyRemote(void Function() fn) {
    suspendSync();
    try {
      fn();
    } finally {
      resumeSync();
    }
  }

  void _applyIncomingNodes(List<NoteNode> incomingNodes) {
    final dirtyIds = _nodeSyncManager.locallyDirtyNodeIds;
    final requests = <EditRequest>[];
    final incomingIds = incomingNodes.map((n) => n.id).toSet();

    for (final node in _document) {
      if (!incomingIds.contains(node.id)) {
        if (dirtyIds.contains(node.id)) continue;
        requests.add(DeleteNodeRequest(nodeId: node.id));
      }
    }

    for (int i = 0; i < incomingNodes.length; i++) {
      final incoming = incomingNodes[i];
      final existingNode = _document.getNodeById(incoming.id);

      if (existingNode == null) {
        final newNode = NodeSyncManager.createNodeFromSchema(incoming);
        requests.add(InsertNodeAtIndexRequest(nodeIndex: i, newNode: newNode));
      } else {
        if (dirtyIds.contains(incoming.id)) continue;

        // Optimization: If the only difference is the task completion status,
        // use ChangeTaskCompletionRequest to avoid rebuilding the widget and jumping.
        if (existingNode is TaskNode && incoming.type == 'task') {
          try {
            final existingData = jsonDecode(NodeSyncManager.nodeData(existingNode)) as Map<String, dynamic>;
            final incomingData = jsonDecode(incoming.data) as Map<String, dynamic>;
            
            final existingWithoutCompleted = Map.from(existingData)..remove('completed');
            final incomingWithoutCompleted = Map.from(incomingData)..remove('completed');
            
            if (_isMapEqual(existingWithoutCompleted, incomingWithoutCompleted)) {
              final isDbCompleted = incomingData['completed'] as bool? ?? false;
              if (existingNode.isComplete != isDbCompleted) {
                requests.add(ChangeTaskCompletionRequest(
                  nodeId: incoming.id,
                  isComplete: isDbCompleted,
                ));
              }
              continue;
            }
          } catch (_) {}
        }

        if (_isNodeEquivalent(existingNode, incoming)) continue;
        final newNode = NodeSyncManager.createNodeFromSchema(incoming);
        requests.add(
          ReplaceNodeRequest(
            existingNodeId: incoming.id,
            newNode: newNode,
          ),
        );
      }
    }

    if (requests.isNotEmpty) {
      _executeAndPreserveSelection(requests);
    }
  }

  void _applyTaskCompletionStates(Map<String, bool> taskCompletionMap) {
    final requests = <EditRequest>[];
    for (final node in _document) {
      if (node is TaskNode) {
        final isDbCompleted = taskCompletionMap[node.id] ?? false;
        if (node.isComplete != isDbCompleted) {
          requests.add(ChangeTaskCompletionRequest(
            nodeId: node.id,
            isComplete: isDbCompleted,
          ));
        }
      }
    }
    if (requests.isNotEmpty) {
      _executeAndPreserveSelection(requests);
    }
  }

  void _executeAndPreserveSelection(List<EditRequest> requests) {
    if (requests.isEmpty) return;

    final composer = _editor.context.composer;
    final oldSelection = composer.selection;

    _editor.execute(requests);

    if (oldSelection != null) {
      final baseNodeExists = _document.getNodeById(oldSelection.base.nodeId) != null;
      final extentNodeExists = _document.getNodeById(oldSelection.extent.nodeId) != null;
      if (baseNodeExists && extentNodeExists) {
        // Clamp selection offsets if the text became shorter
        DocumentSelection finalSelection = oldSelection;
        final baseNode = _document.getNodeById(oldSelection.base.nodeId);
        final extentNode = _document.getNodeById(oldSelection.extent.nodeId);
        
        DocumentPosition? newBase = oldSelection.base;
        DocumentPosition? newExtent = oldSelection.extent;

        if (baseNode is TextNode && oldSelection.base.nodePosition is TextNodePosition) {
          final maxLen = baseNode.text.toPlainText().length;
          final offset = (oldSelection.base.nodePosition as TextNodePosition).offset;
          if (offset > maxLen) {
            newBase = DocumentPosition(
              nodeId: oldSelection.base.nodeId,
              nodePosition: TextNodePosition(offset: maxLen),
            );
          }
        }
        if (extentNode is TextNode && oldSelection.extent.nodePosition is TextNodePosition) {
          final maxLen = extentNode.text.toPlainText().length;
          final offset = (oldSelection.extent.nodePosition as TextNodePosition).offset;
          if (offset > maxLen) {
            newExtent = DocumentPosition(
              nodeId: oldSelection.extent.nodeId,
              nodePosition: TextNodePosition(offset: maxLen),
            );
          }
        }

        finalSelection = DocumentSelection(base: newBase, extent: newExtent);

        if (finalSelection != composer.selection) {
          _editor.execute([
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

  /// Fast-path diff: returns true when an existing document node is
  /// structurally identical to the incoming schema node.
  ///
  /// Uses cheap checks first — type identity, text equality — before
  /// falling back to the full serialisation provided by
  /// [NodeSyncManager.nodeData].
  bool _isNodeEquivalent(DocumentNode existingNode, NoteNode incoming) {
    final existingAttribution = _existingAttribution(existingNode);
    if (existingAttribution != incoming.type) return false;

    // Text-bearing nodes: cheap text comparison first.
    if (existingNode is TextNode &&
        incoming.type != 'image' &&
        incoming.type != 'divider') {
      final data = jsonDecode(incoming.data) as Map<String, dynamic>;
      if (existingNode.text.toPlainText() != (data['text'] as String? ?? '')) {
        return false;
      }
    }

    // Full structural equality via deep Map comparison of serialised data.
    final existingDataStr = NodeSyncManager.nodeData(existingNode);
    try {
      final existingData = jsonDecode(existingDataStr) as Map<String, dynamic>;
      final incomingData = jsonDecode(incoming.data) as Map<String, dynamic>;
      final isEq = _isMapEqual(existingData, incomingData);
      if (!isEq) {
        dev.log(
          '[NoteSync] NODE NOT EQUIVALENT ID=${incoming.id} TYPE=${incoming.type}\n'
          'Existing: $existingData\n'
          'Incoming: $incomingData',
          name: 'SyncService',
        );
      }
      return isEq;
    } catch (_) {
      return false;
    }
  }

  bool _isMapEqual(Map<dynamic, dynamic> a, Map<dynamic, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      final valA = a[key];
      final valB = b[key];
      if (valA is Map && valB is Map) {
        if (!_isMapEqual(valA, valB)) return false;
      } else if (valA is List && valB is List) {
        if (!_isListEqual(valA, valB)) return false;
      } else {
        if (valA != valB) return false;
      }
    }
    return true;
  }

  bool _isListEqual(List<dynamic> a, List<dynamic> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final valA = a[i];
      final valB = b[i];
      if (valA is Map && valB is Map) {
        if (!_isMapEqual(valA, valB)) return false;
      } else if (valA is List && valB is List) {
        if (!_isListEqual(valA, valB)) return false;
      } else {
        if (valA != valB) return false;
      }
    }
    return true;
  }

  String? _existingAttribution(DocumentNode node) {
    if (node is ParagraphNode) {
      final blockType = node.getMetadataValue('blockType') as Attribution?;
      if (blockType == null) return 'paragraph';
      if (blockType == blockquoteAttribution) return 'blockquote';
      return 'header';
    }
    if (node is TaskNode) return 'task';
    if (node is ListItemNode) return 'list_item';
    if (node is HorizontalRuleNode) return 'divider';
    return null;
  }
}

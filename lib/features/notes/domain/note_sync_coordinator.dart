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

  void dispose() => _nodeSyncManager.dispose();

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
      _editor.execute(requests);
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
      _editor.execute(requests);
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

    // Full structural equality via serialisation fallback.
    final existingData = NodeSyncManager.nodeData(existingNode);
    return existingData ==
        NodeSyncManager.nodeData(
          NodeSyncManager.createNodeFromSchema(incoming),
        );
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

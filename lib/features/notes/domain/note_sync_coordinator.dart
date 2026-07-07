import 'package:super_editor/super_editor.dart';

import '../../../core/database/database.dart';
import 'node_sync_manager.dart';

class RemoteNodeApplicator {
  RemoteNodeApplicator({
    required MutableDocument document,
    required Editor editor,
    required Set<String> Function() dirtyNodeIds,
  })  : _document = document,
        _editor = editor,
        _dirtyNodeIds = dirtyNodeIds;

  final MutableDocument _document;
  final Editor _editor;
  final Set<String> Function() _dirtyNodeIds;

  void applyIncomingNodes(List<NoteNode> incomingNodes) {
    final dirtyIds = _dirtyNodeIds();
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
        final newNode = NodeSyncManager.createNodeFromSchema(incoming);
        if (NodeSyncManager.nodeData(existingNode) !=
            NodeSyncManager.nodeData(newNode)) {
          requests.add(
            ReplaceNodeRequest(
              existingNodeId: incoming.id,
              newNode: newNode,
            ),
          );
        }
      }
    }

    if (requests.isNotEmpty) {
      _editor.execute(requests);
    }
  }

  void applyTaskCompletionStates(Map<String, bool> taskCompletionMap) {
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
}

class NoteSyncCoordinator {
  late final NodeSyncManager _nodeSyncManager;
  late final RemoteNodeApplicator _remoteApplicator;

  NoteSyncCoordinator({
    required AppDatabase database,
    required String noteId,
    required String userId,
    required MutableDocument document,
    required Editor editor,
  }) {
    _nodeSyncManager = NodeSyncManager(
      database: database,
      noteId: noteId,
      userId: userId,
      document: document,
    );
    _remoteApplicator = RemoteNodeApplicator(
      document: document,
      editor: editor,
      dirtyNodeIds: () => _nodeSyncManager.locallyDirtyNodeIds,
    );
  }

  Set<String> get locallyDirtyNodeIds =>
      _nodeSyncManager.locallyDirtyNodeIds;

  void updateNodesIncrementally(List<NoteNode> incomingNodes) {
    suspendSync();
    try {
      _remoteApplicator.applyIncomingNodes(incomingNodes);
    } finally {
      resumeSync();
    }
  }

  void syncTaskStates(Map<String, bool> taskCompletionMap) {
    suspendSync();
    try {
      _remoteApplicator.applyTaskCompletionStates(taskCompletionMap);
    } finally {
      resumeSync();
    }
  }

  void suspendSync() => _nodeSyncManager.suspendSync();

  void resumeSync() => _nodeSyncManager.resumeSync();

  void dispose() => _nodeSyncManager.dispose();
}

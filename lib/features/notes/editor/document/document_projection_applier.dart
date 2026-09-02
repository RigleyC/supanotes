import 'dart:convert';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/debug/note_sync_debug.dart';
import 'package:supanotes/features/notes/editor/document/effective_document_projector.dart';
import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';
import 'package:supanotes/features/notes/editor/document/note_document_constants.dart';
import 'package:supanotes/features/notes/editor/sync/note_operation_contract.dart';
import 'package:super_editor/super_editor.dart';

class DocumentProjectionApplier {
  DocumentProjectionApplier({
    required MutableDocument document,
    required Editor editor,
    required NoteDocumentCodec codec,
  }) : _document = document,
       _editor = editor,
       _codec = codec;
  final MutableDocument _document;
  final Editor _editor;
  final NoteDocumentCodec _codec;
  late final EffectiveDocumentProjector _effectiveProjector =
      EffectiveDocumentProjector(codec: _codec);

  Future<void> rebuildFromSnapshot({
    required Map<String, dynamic> snapshot,
    required List<PendingNoteOperationData>? pendingOps,
    required bool repairPersistedSnapshot,
    required void Function() suppressCapture,
    required void Function() resumeCapture,
    required void Function() rebuildMirror,
  }) async {
    suppressCapture();
    final previousSelection = _editor.context
        .find<MutableDocumentComposer>(Editor.composerKey)
        .selection;
    NoteSyncDebug.log(
      'projection.rebuild.begin',
      fields: {
        'currentNodeCount': _document.nodeCount,
        'pendingOperations': pendingOps?.length ?? 0,
        'snapshot': NoteSyncDebug.documentSummary(snapshot),
        'selection': previousSelection,
      },
    );

    if (!repairPersistedSnapshot &&
        _matchesCurrentEffectiveDoc(
          snapshot: snapshot,
          pendingOps: pendingOps,
        )) {
      NoteSyncDebug.log(
        'projection.rebuild.skip_effective_doc',
        fields: {
          'pendingOperations': pendingOps?.length ?? 0,
          'nodeCount': _document.nodeCount,
          'selection': previousSelection,
        },
      );
      rebuildMirror();
      resumeCapture();
      return;
    }

    var rebuildCompleted = false;
    try {
      _editor.startTransaction();
      _editor.execute([
        const ChangeSelectionRequest(
          null,
          SelectionChangeType.clearSelection,
          SelectionReason.contentChange,
        ),
      ]);

      final existingNodes = _document.toList();
      for (final node in existingNodes.reversed) {
        _editor.execute([DeleteNodeRequest(nodeId: node.id)]);
      }

      applyFullDocument(
        snapshot,
        repairPersistedSnapshot: repairPersistedSnapshot,
      );

      if (pendingOps != null) {
        for (final op in pendingOps) {
          final payload = jsonDecode(op.payloadJson) as Map<String, dynamic>;
          NoteSyncDebug.log(
            'projection.apply_pending',
            fields: {
              'operationId': op.operationId,
              'kind': op.kind,
              'blockId': op.blockId,
              'payload': NoteSyncDebug.payloadSummary(payload),
            },
          );
          applyOperationPayload(
            kind: op.kind,
            blockId: op.blockId,
            payload: payload,
          );
        }
      }

      rebuildMirror();
      rebuildCompleted = true;
    } finally {
      final selection = _selectionAfterRebuild(previousSelection);
      NoteSyncDebug.log(
        'projection.rebuild.end',
        fields: {'nodeCount': _document.nodeCount, 'selection': selection},
      );
      _editor.execute([
        ChangeSelectionRequest(
          selection,
          SelectionChangeType.alteredContent,
          SelectionReason.contentChange,
        ),
      ]);
      _editor.endTransaction();
      if (rebuildCompleted) resumeCapture();
    }
  }

  void applyFullDocument(
    Map<String, dynamic> snapshot, {
    required bool repairPersistedSnapshot,
  }) {
    final blocks = snapshot['blocks'] as List<dynamic>? ?? [];
    if (blocks.isEmpty) {
      _editor.execute([
        InsertNodeAtIndexRequest(
          newNode: ParagraphNode(
            id: initialNoteBlockId,
            text: AttributedText(),
          ),
          nodeIndex: 0,
        ),
      ]);
      return;
    }

    final insertedNodeIds = <String>{};
    var nodeIndex = 0;
    for (final block in blocks) {
      final b = block as Map<String, dynamic>;
      final node = repairPersistedSnapshot
          ? _codec.decodePersistedNode(b)
          : _codec.decodeNode(b);
      if (!insertedNodeIds.add(node.id)) {
        NoteSyncDebug.log(
          'projection.snapshot.duplicate_node_id',
          fields: {'nodeId': node.id},
        );
        continue;
      }
      _editor.execute([
        InsertNodeAtIndexRequest(newNode: node, nodeIndex: nodeIndex),
      ]);
      nodeIndex++;
    }
  }

  void applyOperationPayload({
    required String kind,
    required String? blockId,
    required Map<String, dynamic> payload,
  }) {
    switch (kind) {
      case NoteOperationWireNames.textDelta:
        _applyTextDelta(blockId, payload);
      case NoteOperationWireNames.createBlock:
        _applyCreateBlock(payload);
      case NoteOperationWireNames.deleteBlock:
        _applyDeleteBlock(blockId);
      case NoteOperationWireNames.moveBlock:
        _applyMoveBlock(blockId, payload);
      case NoteOperationWireNames.setBlockType:
        _applySetBlockType(blockId, payload);
      case NoteOperationWireNames.setBlockMetadata:
        _applySetBlockMetadata(blockId, payload);
      case NoteOperationWireNames.completeTaskOccurrence:
        _applyCompleteTaskOccurrence(blockId, payload);
    }
  }

  void _applyTextDelta(String? blockId, Map<String, dynamic> payload) {
    if (blockId == null) return;
    final node = _document.getNodeById(blockId);
    if (node is! TextNode) return;

    final rawOps = payload['ops'] as List<dynamic>?;
    if (rawOps == null) return;

    final ops = rawOps.cast<Map<String, dynamic>>();
    final newText = _codec.applyDeltaToText(node.text, ops);
    if (newText == null) return;

    _replaceNode(blockId, _createNodeWithUpdatedText(node, newText));
  }

  void _applyCreateBlock(Map<String, dynamic> payload) {
    final node = _codec.decodeNode(payload);
    if (_document.getNodeById(node.id) != null) {
      NoteSyncDebug.log(
        'projection.create.skip_duplicate',
        fields: {'nodeId': node.id},
      );
      return;
    }

    final afterBlockId = payload['afterBlockId'] as String?;
    var insertIndex = _document.nodeCount;
    if (afterBlockId != null) {
      final targetNode = _document.getNodeById(afterBlockId);
      if (targetNode != null) {
        insertIndex = _document.getNodeIndexById(targetNode.id) + 1;
      }
    } else {
      insertIndex = 0;
    }
    _editor.execute([
      InsertNodeAtIndexRequest(newNode: node, nodeIndex: insertIndex),
    ]);
  }

  void _applyDeleteBlock(String? blockId) {
    if (blockId == null) return;
    final node = _document.getNodeById(blockId);
    if (node != null && _document.nodeCount > 1) {
      _editor.execute([DeleteNodeRequest(nodeId: blockId)]);
    }
  }

  void _applyMoveBlock(String? blockId, Map<String, dynamic> payload) {
    final moveBlockId = payload['blockId'] as String? ?? blockId;
    if (moveBlockId == null) return;
    final node = _document.getNodeById(moveBlockId);
    if (node == null || _document.nodeCount <= 1) return;

    final sourceIndex = _document.getNodeIndexById(moveBlockId);
    final afterBlockId = payload['afterBlockId'] as String?;
    if (afterBlockId == moveBlockId) return;
    var targetIndex = _document.nodeCount - 1;
    if (afterBlockId == null) {
      targetIndex = 0;
    } else {
      final targetNode = _document.getNodeById(afterBlockId);
      if (targetNode != null) {
        final targetNodeIndex = _document.getNodeIndexById(targetNode.id);
        targetIndex = targetNodeIndex + 1;
        if (sourceIndex < targetNodeIndex) {
          targetIndex -= 1;
        }
      }
    }
    _editor.execute([
      MoveNodeRequest(nodeId: moveBlockId, newIndex: targetIndex),
    ]);
  }

  void _applySetBlockType(String? blockId, Map<String, dynamic> payload) {
    if (blockId == null) return;
    final newType = payload['type'] as String? ?? 'paragraph';
    final node = _document.getNodeById(blockId);
    if (node == null) return;

    final text = (node is TextNode) ? node.text : AttributedText();
    final isComplete = (node is TaskNode) && node.isComplete;
    final newNode = _codec.createNodeFromBlockType(
      nodeId: blockId,
      type: newType,
      text: text,
      isTaskComplete: isComplete,
      metadata: Map<String, dynamic>.from(node.metadata),
    );
    _editor.execute([
      ReplaceNodeRequest(existingNodeId: blockId, newNode: newNode),
    ]);
  }

  void _applySetBlockMetadata(String? blockId, Map<String, dynamic> payload) {
    if (blockId == null) return;
    final node = _document.getNodeById(blockId);
    final meta = payload['metadata'] as Map<String, dynamic>?;
    if (node == null || meta == null) return;

    _replaceNode(blockId, _createNodeWithUpdatedMetadata(node, meta));
  }

  void _applyCompleteTaskOccurrence(
    String? blockId,
    Map<String, dynamic> payload,
  ) {
    final targetId = blockId ?? payload['taskId'] as String?;
    if (targetId == null) return;
    final node = _document.getNodeById(targetId);
    final scheduledAt = payload['scheduledAt'] as String?;
    final completedAt = payload['completedAt'] as String?;
    if (node is! TaskNode || scheduledAt == null) return;

    final currentCompletions = Map<String, dynamic>.from(
      node.metadata['completions'] as Map? ?? {},
    );
    if (completedAt != null && completedAt.isNotEmpty) {
      currentCompletions[scheduledAt] = completedAt;
    } else {
      currentCompletions.remove(scheduledAt);
    }
    final newNode = _createNodeWithUpdatedMetadata(node, {
      'completions': currentCompletions,
    });
    _replaceNode(targetId, newNode);
  }

  bool _matchesCurrentEffectiveDoc({
    required Map<String, dynamic> snapshot,
    required List<PendingNoteOperationData>? pendingOps,
  }) {
    final projected = _effectiveProjector.projectBlocks(
      snapshot: snapshot,
      pendingOps: pendingOps,
    );
    final current = _codec.encodeDocument(_document);
    return _sameBlockList(projected, current);
  }

  static bool _sameBlockList(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameJsonValue(a[i], b[i])) return false;
    }
    return true;
  }

  static bool _sameJsonValue(dynamic a, dynamic b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final entry in a.entries) {
        if (!b.containsKey(entry.key)) return false;
        if (!_sameJsonValue(entry.value, b[entry.key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_sameJsonValue(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  DocumentSelection? _selectionAfterRebuild(DocumentSelection? previous) {
    if (previous == null) return null;

    DocumentPosition? positionFor(DocumentPosition position) {
      final node = _document.getNodeById(position.nodeId);
      if (node is! TextNode || position.nodePosition is! TextNodePosition) {
        return null;
      }

      final textPosition = position.nodePosition as TextNodePosition;
      return DocumentPosition(
        nodeId: node.id,
        nodePosition: TextNodePosition(
          offset: textPosition.offset.clamp(0, node.text.length),
          affinity: textPosition.affinity,
        ),
      );
    }

    final base = positionFor(previous.base);
    final extent = positionFor(previous.extent);
    if (base == null || extent == null) return null;
    return DocumentSelection(base: base, extent: extent);
  }

  DocumentNode _createNodeWithUpdatedText(
    TextNode node,
    AttributedText newText,
  ) {
    if (node is TaskNode) {
      return TaskNode(
        id: node.id,
        text: newText,
        isComplete: node.isComplete,
        indent: node.indent,
        metadata: Map.from(node.metadata),
      );
    } else if (node is ListItemNode) {
      return ListItemNode(
        id: node.id,
        itemType: node.type,
        text: newText,
        indent: node.indent,
        metadata: Map.from(node.metadata),
      );
    } else if (node is ParagraphNode) {
      return ParagraphNode(
        id: node.id,
        text: newText,
        indent: node.indent,
        metadata: Map.from(node.metadata),
      );
    }
    return ParagraphNode(id: node.id, text: newText);
  }

  void _replaceNode(String nodeId, DocumentNode newNode) {
    _editor.execute([
      ReplaceNodeRequest(existingNodeId: nodeId, newNode: newNode),
    ]);
    if (newNode is TaskNode && newNode.indent > 0) {
      // Super Editor treats a task replacement as a deletion while normalizing
      // task indentation. Restore the existing level after that reaction.
      _editor.execute([SetTaskIndentRequest(newNode.id, newNode.indent)]);
    }
  }

  DocumentNode _createNodeWithUpdatedMetadata(
    DocumentNode node,
    Map<String, dynamic> meta,
  ) {
    final updatedMeta = _mergeMetadata(node.metadata, meta);
    _normalizeBlockType(updatedMeta);

    if (node is TaskNode) {
      return TaskNode(
        id: node.id,
        text: node.text,
        isComplete: _updatedCompletion(node, meta),
        indent: _updatedIndent(node.indent, meta),
        metadata: updatedMeta,
      );
    } else if (node is ParagraphNode) {
      return ParagraphNode(
        id: node.id,
        text: node.text,
        indent: _updatedIndent(node.indent, meta),
        metadata: updatedMeta,
      );
    } else if (node is ListItemNode) {
      return ListItemNode(
        id: node.id,
        itemType: node.type,
        text: node.text,
        indent: _updatedIndent(node.indent, meta),
        metadata: updatedMeta,
      );
    }
    return node;
  }

  Map<String, dynamic> _mergeMetadata(
    Map<String, dynamic> current,
    Map<String, dynamic> updates,
  ) {
    final merged = Map<String, dynamic>.from(current);
    for (final entry in updates.entries) {
      if (entry.value == null) {
        merged.remove(entry.key);
      } else {
        merged[entry.key] = entry.value;
      }
    }
    return merged;
  }

  void _normalizeBlockType(Map<String, dynamic> metadata) {
    if (!metadata.containsKey('blockType')) return;

    final rawBlockType = metadata['blockType'];
    if (rawBlockType is String) {
      final attribution = _codec.attributionFromName(rawBlockType);
      if (attribution != null) {
        metadata['blockType'] = attribution;
      } else {
        metadata.remove('blockType');
      }
    } else if (rawBlockType == null) {
      metadata.remove('blockType');
    }
  }

  bool _updatedCompletion(TaskNode node, Map<String, dynamic> metadata) {
    return metadata.containsKey('isCompleted')
        ? metadata['isCompleted'] as bool
        : node.isComplete;
  }

  int _updatedIndent(int currentIndent, Map<String, dynamic> metadata) {
    return metadata.containsKey('indent')
        ? metadata['indent'] as int? ?? 0
        : currentIndent;
  }
}

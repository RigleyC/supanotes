import 'dart:convert';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/database/database.dart';
import 'ot_document_codec.dart';

class DocumentProjectionApplier {
  final MutableDocument _document;
  final Editor _editor;
  final OtDocumentCodec _codec;

  DocumentProjectionApplier({
    required MutableDocument document,
    required Editor editor,
    required OtDocumentCodec codec,
  })  : _document = document,
        _editor = editor,
        _codec = codec;

  Future<void> rebuildFromSnapshot({
    required Map<String, dynamic> snapshot,
    required List<PendingNoteOperationData>? pendingOps,
    required void Function() suppressCapture,
    required void Function() resumeCapture,
    required void Function() rebuildMirror,
  }) async {
    final composer = _editor.context.composer;
    final oldSelection = composer.selection;

    suppressCapture();
    try {
      // Clear selection before deleting nodes so IME/layers don't dereference deleted nodes during rebuild
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

      applyFullDocument(snapshot);

      if (pendingOps != null) {
        for (final op in pendingOps) {
          final payload = jsonDecode(op.payloadJson) as Map<String, dynamic>;
          applyOperationPayload(
            kind: op.kind,
            blockId: op.blockId,
            payload: payload,
          );
        }
      }

      rebuildMirror();

      // Restore selection if target node still exists
      if (oldSelection != null) {
        final node = _document.getNodeById(oldSelection.extent.nodeId);
        if (node != null) {
          _editor.execute([
            ChangeSelectionRequest(
              oldSelection,
              SelectionChangeType.placeCaret,
              SelectionReason.contentChange,
            ),
          ]);
        }
      }
    } finally {
      resumeCapture();
    }
  }

  void applyFullDocument(Map<String, dynamic> snapshot) {
    final blocks = snapshot['blocks'] as List<dynamic>? ?? [];
    if (blocks.isEmpty) {
      _editor.execute([
        InsertNodeAtIndexRequest(
          newNode: ParagraphNode(id: 'init', text: AttributedText()),
          nodeIndex: 0,
        ),
      ]);
      return;
    }

    for (int i = 0; i < blocks.length; i++) {
      final b = blocks[i] as Map<String, dynamic>;
      final node = _codec.decodeNode(b);
      _editor.execute([
        InsertNodeAtIndexRequest(
          newNode: node,
          nodeIndex: i,
        ),
      ]);
    }
  }

  void applyOperationPayload({
    required String kind,
    required String? blockId,
    required Map<String, dynamic> payload,
  }) {
    switch (kind) {
      case 'text_delta':
        if (blockId == null) return;
        final node = _document.getNodeById(blockId);
        if (node is TextNode) {
          final rawOps = payload['ops'] as List<dynamic>?;
          if (rawOps != null) {
            final ops = rawOps.cast<Map<String, dynamic>>();
            final newText = _codec.applyDeltaToText(node.text, ops);
            if (newText != null) {
              final newNode = _createNodeWithUpdatedText(node, newText);
              _editor.execute([
                ReplaceNodeRequest(
                  existingNodeId: blockId,
                  newNode: newNode,
                ),
              ]);
            }
          }
        }
        break;
      case 'create_block':
        final node = _codec.decodeNode(payload);
        final afterBlockId = payload['afterBlockId'] as String?;
        int insertIndex = _document.nodeCount;
        if (afterBlockId != null) {
          final targetNode = _document.getNodeById(afterBlockId);
          if (targetNode != null) {
            insertIndex = _document.getNodeIndexById(targetNode.id) + 1;
          }
        } else {
          insertIndex = 0;
        }
        _editor.execute([
          InsertNodeAtIndexRequest(
            newNode: node,
            nodeIndex: insertIndex,
          ),
        ]);
        break;
      case 'delete_block':
        if (blockId == null) return;
        final node = _document.getNodeById(blockId);
        if (node != null && _document.nodeCount > 1) {
          _editor.execute([DeleteNodeRequest(nodeId: blockId)]);
        }
        break;
      case 'move_block':
        final moveBlockId = payload['blockId'] as String? ?? blockId;
        if (moveBlockId == null) return;
        final node = _document.getNodeById(moveBlockId);
        if (node == null) return;

        final afterBlockId = payload['afterBlockId'] as String?;
        int targetIndex = _document.nodeCount - 1;
        if (afterBlockId == null) {
          targetIndex = 0;
        } else {
          final targetNode = _document.getNodeById(afterBlockId);
          if (targetNode != null) {
            targetIndex = _document.getNodeIndexById(targetNode.id) + 1;
          }
        }
        _editor.execute([
          MoveNodeRequest(
            nodeId: moveBlockId,
            newIndex: targetIndex,
          ),
        ]);
        break;
      case 'set_block_type':
        if (blockId == null) return;
        final newType = payload['type'] as String? ?? 'paragraph';
        final node = _document.getNodeById(blockId);
        if (node != null) {
          final text = (node is TextNode) ? node.text : AttributedText();
          final isComplete = (node is TaskNode) ? node.isComplete : false;
          final newNode = _codec.createNodeFromBlockType(
            nodeId: blockId,
            type: newType,
            text: text,
            isTaskComplete: isComplete,
          );
          _editor.execute([
            ReplaceNodeRequest(
              existingNodeId: blockId,
              newNode: newNode,
            ),
          ]);
        }
        break;
      case 'set_block_metadata':
        if (blockId == null) return;
        final node = _document.getNodeById(blockId);
        final meta = payload['metadata'] as Map<String, dynamic>?;
        if (node != null && meta != null) {
          final newNode = _createNodeWithUpdatedMetadata(node, meta);
          _editor.execute([
            ReplaceNodeRequest(
              existingNodeId: blockId,
              newNode: newNode,
            ),
          ]);
        }
        break;
      case 'complete_task_occurrence':
        final targetId = blockId ?? payload['taskId'] as String?;
        if (targetId == null) return;
        final node = _document.getNodeById(targetId);
        final scheduledAt = payload['scheduledAt'] as String?;
        final completedAt = payload['completedAt'] as String?;
        if (node is TaskNode && scheduledAt != null) {
          final currentCompletions = Map<String, dynamic>.from(
            node.metadata['completions'] as Map? ?? {},
          );
          if (completedAt != null && completedAt.isNotEmpty) {
            currentCompletions[scheduledAt] = completedAt;
          } else {
            currentCompletions.remove(scheduledAt);
          }
          final newNode = _createNodeWithUpdatedMetadata(
            node,
            {'completions': currentCompletions},
          );
          _editor.execute([
            ReplaceNodeRequest(
              existingNodeId: targetId,
              newNode: newNode,
            ),
          ]);
        }
        break;
    }
  }

  DocumentNode _createNodeWithUpdatedText(TextNode node, AttributedText newText) {
    if (node is TaskNode) {
      return TaskNode(
        id: node.id,
        text: newText,
        isComplete: node.isComplete,
        metadata: Map.from(node.metadata),
      );
    } else if (node is ListItemNode) {
      return ListItemNode(
        id: node.id,
        itemType: node.type,
        text: newText,
        metadata: Map.from(node.metadata),
      );
    } else if (node is ParagraphNode) {
      return ParagraphNode(
        id: node.id,
        text: newText,
        metadata: Map.from(node.metadata),
      );
    }
    return ParagraphNode(
      id: node.id,
      text: newText,
    );
  }

  DocumentNode _createNodeWithUpdatedMetadata(
    DocumentNode node,
    Map<String, dynamic> meta,
  ) {
    final updatedMeta = Map<String, dynamic>.from(node.metadata);
    for (final entry in meta.entries) {
      if (entry.value == null) {
        updatedMeta.remove(entry.key);
      } else {
        updatedMeta[entry.key] = entry.value;
      }
    }

    if (node is TaskNode) {
      final isComp = meta.containsKey('isCompleted')
          ? meta['isCompleted'] as bool
          : node.isComplete;
      return TaskNode(
        id: node.id,
        text: node.text,
        isComplete: isComp,
        metadata: updatedMeta,
      );
    } else if (node is ParagraphNode) {
      return ParagraphNode(
        id: node.id,
        text: node.text,
        metadata: updatedMeta,
      );
    } else if (node is ListItemNode) {
      return ListItemNode(
        id: node.id,
        itemType: node.type,
        text: node.text,
        metadata: updatedMeta,
      );
    }
    return node;
  }
}

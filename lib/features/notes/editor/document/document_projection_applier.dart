import 'dart:convert';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/debug/note_sync_debug.dart';
import 'package:supanotes/features/notes/editor/document/document_node_transforms.dart';
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
  late final DocumentNodeTransforms _transforms = DocumentNodeTransforms(
    _codec,
  );
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
    // The selection is never cleared while applying an update. Clearing it
    // trips the IME policy that closes the keyboard on selection loss, which
    // destroys the platform composing state mid-typing and makes the next
    // keystrokes land at stale offsets.
    final composer = _editor.maybeComposer;
    final previousSelection = composer?.selection;
    NoteSyncDebug.log(
      'projection.rebuild.begin',
      fields: {
        'currentNodeCount': _document.nodeCount,
        'pendingOperations': pendingOps?.length ?? 0,
        'snapshot': NoteSyncDebug.documentSummary(snapshot),
        'selection': previousSelection,
      },
    );

    // Malformed snapshots must fail before the transaction starts so the
    // capture suppression from the caller is observed by existing tests.
    List<Map<String, dynamic>>? projected;
    if (!repairPersistedSnapshot) {
      projected = _effectiveProjector.projectBlocks(
        snapshot: snapshot,
        pendingOps: pendingOps,
      );
      if (_sameBlockList(projected, _codec.encodeDocument(_document))) {
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
    }

    final textEdits = <String, _TextReplacement>{};
    var rebuildCompleted = false;
    try {
      _editor.startTransaction();
      if (repairPersistedSnapshot) {
        // Startup hydration keeps the wholesale rebuild: the document is not
        // attached to a live IME session yet, and the persisted snapshot
        // needs its repair decoding.
        _rebuildWholesale(snapshot: snapshot, pendingOps: pendingOps);
      } else {
        _applyProjectedIncrementally(projected!, textEdits);
      }
      rebuildMirror();
      rebuildCompleted = true;
    } finally {
      final selection = _mapSelectionAfterApply(previousSelection, textEdits);
      NoteSyncDebug.log(
        'projection.rebuild.end',
        fields: {'nodeCount': _document.nodeCount, 'selection': selection},
      );
      // Only touch the composer when the apply actually moved the selection.
      // An unmoved caret must not emit any selection change, otherwise the
      // IME sees churn on every reconciliation.
      if (!_sameSelection(composer?.selection, selection)) {
        _editor.execute([
          ChangeSelectionRequest(
            selection,
            SelectionChangeType.alteredContent,
            SelectionReason.contentChange,
          ),
        ]);
      }
      _editor.endTransaction();
      if (rebuildCompleted) resumeCapture();
    }
  }

  void _rebuildWholesale({
    required Map<String, dynamic> snapshot,
    required List<PendingNoteOperationData>? pendingOps,
  }) {
    final existingNodes = _document.toList();
    for (final node in existingNodes.reversed) {
      _editor.execute([DeleteNodeRequest(nodeId: node.id)]);
    }

    applyFullDocument(snapshot, repairPersistedSnapshot: true);

    if (pendingOps == null) return;
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

  /// Applies the projected blocks by touching only what differs.
  ///
  /// Blocks whose encoded content already matches the projection keep their
  /// exact node instance, so the widgets (and the focused text component)
  /// of the blocks the user is editing survive a reconciliation.
  void _applyProjectedIncrementally(
    List<Map<String, dynamic>> projected,
    Map<String, _TextReplacement> textEdits,
  ) {
    final projectedById = <String, Map<String, dynamic>>{};
    for (final block in projected) {
      final id = block['id'] as String?;
      if (id == null) continue;
      projectedById.putIfAbsent(id, () => block);
    }

    for (final node in _document.toList()) {
      if (!projectedById.containsKey(node.id)) {
        _editor.execute([DeleteNodeRequest(nodeId: node.id)]);
      }
    }

    var insertedCount = 0;
    var replacedCount = 0;
    var movedCount = 0;
    for (var i = 0; i < projected.length; i++) {
      final block = projected[i];
      final id = block['id'] as String;
      final existing = _document.getNodeById(id);
      if (existing == null) {
        _editor.execute([
          InsertNodeAtIndexRequest(
            newNode: _codec.decodeNode(block),
            nodeIndex: i,
          ),
        ]);
        insertedCount++;
        continue;
      }

      if (!_sameJsonValue(_codec.encodeNode(existing), block)) {
        final oldNode = existing;
        final newNode = _codec.decodeNode(block);
        if (oldNode is TextNode && newNode is TextNode) {
          final oldText = oldNode.text.toPlainText();
          final newText = newNode.text.toPlainText();
          if (oldText != newText) {
            textEdits[id] = _TextReplacement(
              oldText: oldText,
              newText: newText,
            );
          }
        }
        _replaceNode(id, newNode);
        replacedCount++;
      }

      final actualIndex = _document.getNodeIndexById(id);
      if (actualIndex != i) {
        _editor.execute([MoveNodeRequest(nodeId: id, newIndex: i)]);
        movedCount++;
      }
    }

    NoteSyncDebug.log(
      'projection.apply.incremental',
      fields: {
        'inserted': insertedCount,
        'replaced': replacedCount,
        'moved': movedCount,
        'nodeCount': _document.nodeCount,
      },
    );
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

    _replaceNode(blockId, _transforms.withText(node, newText));
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

    _replaceNode(blockId, _transforms.withMetadata(node, meta));
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
    final newNode = _transforms.withMetadata(node, {
      'completions': currentCompletions,
    });
    _replaceNode(targetId, newNode);
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

  /// Maps the selection through an incremental apply.
  ///
  /// Positions in untouched nodes keep their offsets. Positions inside a
  /// block whose text changed are shifted with a common prefix/suffix diff,
  /// so a remote insert before the caret moves the caret instead of letting
  /// the next keystroke land at a stale offset.
  DocumentSelection? _mapSelectionAfterApply(
    DocumentSelection? previous,
    Map<String, _TextReplacement> textEdits,
  ) {
    if (previous == null) return null;

    DocumentPosition? positionFor(DocumentPosition position) {
      final node = _document.getNodeById(position.nodeId);
      if (node is! TextNode || position.nodePosition is! TextNodePosition) {
        return null;
      }

      final textPosition = position.nodePosition as TextNodePosition;
      var offset = textPosition.offset;
      final edit = textEdits[position.nodeId];
      if (edit != null) {
        offset = edit.mapOffset(offset);
      }
      return DocumentPosition(
        nodeId: node.id,
        nodePosition: TextNodePosition(
          offset: offset.clamp(0, node.text.length),
          affinity: textPosition.affinity,
        ),
      );
    }

    final base = positionFor(previous.base);
    final extent = positionFor(previous.extent);
    if (base == null || extent == null) return null;
    return DocumentSelection(base: base, extent: extent);
  }

  static bool _sameSelection(DocumentSelection? a, DocumentSelection? b) {
    if (a == null || b == null) return a == null && b == null;
    return _samePosition(a.base, b.base) && _samePosition(a.extent, b.extent);
  }

  static bool _samePosition(DocumentPosition a, DocumentPosition b) {
    if (a.nodeId != b.nodeId) return false;
    final aPosition = a.nodePosition;
    final bPosition = b.nodePosition;
    if (aPosition is TextNodePosition && bPosition is TextNodePosition) {
      return aPosition.offset == bPosition.offset &&
          aPosition.affinity == bPosition.affinity;
    }
    return aPosition == bPosition;
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
}

/// A text change applied to one block during an incremental rebuild.
class _TextReplacement {
  const _TextReplacement({required this.oldText, required this.newText});

  final String oldText;
  final String newText;

  /// Shifts [offset] from the old text into the new text.
  ///
  /// Offsets inside the unchanged prefix stay put; offsets inside the
  /// unchanged suffix shift by the length delta; offsets inside the edited
  /// middle collapse to the end of the prefix.
  int mapOffset(int offset) {
    if (oldText == newText) return offset;

    var prefix = 0;
    final maxPrefix =
        oldText.length < newText.length ? oldText.length : newText.length;
    while (prefix < maxPrefix &&
        oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
      prefix++;
    }

    var suffix = 0;
    final maxSuffix = maxPrefix - prefix;
    while (suffix < maxSuffix &&
        oldText.codeUnitAt(oldText.length - 1 - suffix) ==
            newText.codeUnitAt(newText.length - 1 - suffix)) {
      suffix++;
    }

    if (offset <= prefix) return offset;
    final oldEnd = oldText.length - suffix;
    if (offset >= oldEnd) {
      final shifted = offset + (newText.length - oldText.length);
      if (shifted < 0) return 0;
      if (shifted > newText.length) return newText.length;
      return shifted;
    }
    return prefix;
  }
}

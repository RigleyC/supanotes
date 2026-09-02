import 'dart:convert';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';
import 'package:supanotes/features/notes/editor/document/note_document_constants.dart';
import 'package:supanotes/features/notes/editor/sync/note_operation_contract.dart';
import 'package:super_editor/super_editor.dart';

/// Pure projection of the effective local document: canonical snapshot plus
/// durable local operations that have not been acknowledged by the server.
final class EffectiveDocumentProjector {
  const EffectiveDocumentProjector({
    NoteDocumentCodec codec = const NoteDocumentCodec(),
  }) : _codec = codec;

  final NoteDocumentCodec _codec;

  Map<String, dynamic> project({
    required Map<String, dynamic> snapshot,
    required List<PendingNoteOperationData>? pendingOps,
  }) {
    final nodes = _projectNodes(snapshot, pendingOps);
    return {
      'schemaVersion': snapshot['schemaVersion'] ?? 1,
      'blocks': nodes.map(_codec.encodeNode).toList(growable: false),
    };
  }

  /// Projects only the encoded block list for callers that already own a
  /// document envelope, such as the editor's equality check.
  List<Map<String, dynamic>> projectBlocks({
    required Map<String, dynamic> snapshot,
    required List<PendingNoteOperationData>? pendingOps,
  }) {
    return _projectNodes(
      snapshot,
      pendingOps,
    ).map(_codec.encodeNode).toList(growable: false);
  }

  List<DocumentNode> _projectNodes(
    Map<String, dynamic> snapshot,
    List<PendingNoteOperationData>? pendingOps,
  ) {
    final nodes = _decodeSnapshot(snapshot);
    for (final op in pendingOps ?? const <PendingNoteOperationData>[]) {
      _apply(
        nodes,
        kind: op.kind,
        blockId: op.blockId,
        payload: Map<String, dynamic>.from(jsonDecode(op.payloadJson) as Map),
      );
    }
    return nodes;
  }

  List<DocumentNode> _decodeSnapshot(Map<String, dynamic> snapshot) {
    final blocks = snapshot['blocks'] as List<dynamic>? ?? const [];
    if (blocks.isEmpty) {
      return [
        ParagraphNode(id: initialNoteBlockId, text: AttributedText()),
      ];
    }
    final nodes = <DocumentNode>[];
    final ids = <String>{};
    for (final raw in blocks) {
      final node = _codec.decodeNode(Map<String, dynamic>.from(raw as Map));
      if (ids.add(node.id)) nodes.add(node);
    }
    return nodes;
  }

  void _apply(
    List<DocumentNode> nodes, {
    required String kind,
    required String? blockId,
    required Map<String, dynamic> payload,
  }) {
    switch (kind) {
      case NoteOperationWireNames.textDelta:
        _textDelta(nodes, blockId, payload);
      case NoteOperationWireNames.createBlock:
        _createBlock(nodes, payload);
      case NoteOperationWireNames.deleteBlock:
        _deleteBlock(nodes, blockId);
      case NoteOperationWireNames.moveBlock:
        _moveBlock(nodes, blockId, payload);
      case NoteOperationWireNames.setBlockType:
        _setBlockType(nodes, blockId, payload);
      case NoteOperationWireNames.setBlockMetadata:
        _setBlockMetadata(nodes, blockId, payload);
      case NoteOperationWireNames.completeTaskOccurrence:
        _completeTaskOccurrence(nodes, blockId, payload);
    }
  }

  void _textDelta(
    List<DocumentNode> nodes,
    String? blockId,
    Map<String, dynamic> payload,
  ) {
    if (blockId == null) return;
    final index = nodes.indexWhere((node) => node.id == blockId);
    if (index < 0 || nodes[index] is! TextNode) return;
    final rawOps = payload['ops'] as List<dynamic>?;
    if (rawOps == null) return;
    final node = nodes[index] as TextNode;
    final newText = _codec.applyDeltaToText(
      node.text,
      rawOps.cast<Map<String, dynamic>>(),
    );
    if (newText == null) return;
    nodes[index] = _withText(node, newText);
  }

  void _createBlock(
    List<DocumentNode> nodes,
    Map<String, dynamic> payload,
  ) {
    final node = _codec.decodeNode(payload);
    if (nodes.any((existing) => existing.id == node.id)) return;
    final afterBlockId = payload['afterBlockId'] as String?;
    var index = nodes.length;
    if (afterBlockId == null) {
      index = 0;
    } else {
      final target = nodes.indexWhere(
        (existing) => existing.id == afterBlockId,
      );
      if (target >= 0) index = target + 1;
    }
    nodes.insert(index.clamp(0, nodes.length), node);
  }

  void _deleteBlock(List<DocumentNode> nodes, String? blockId) {
    if (blockId == null || nodes.length <= 1) return;
    final index = nodes.indexWhere((node) => node.id == blockId);
    if (index >= 0) nodes.removeAt(index);
  }

  void _moveBlock(
    List<DocumentNode> nodes,
    String? blockId,
    Map<String, dynamic> payload,
  ) {
    final moveId = payload['blockId'] as String? ?? blockId;
    if (moveId == null || nodes.length <= 1) return;
    final source = nodes.indexWhere((node) => node.id == moveId);
    if (source < 0) return;
    final afterId = payload['afterBlockId'] as String?;
    if (afterId == moveId) return;
    var target = nodes.length - 1;
    if (afterId == null) {
      target = 0;
    } else {
      final afterIndex = nodes.indexWhere((node) => node.id == afterId);
      if (afterIndex >= 0) {
        target = afterIndex + 1;
        if (source < afterIndex) target -= 1;
      }
    }
    final node = nodes.removeAt(source);
    nodes.insert(target.clamp(0, nodes.length), node);
  }

  void _setBlockType(
    List<DocumentNode> nodes,
    String? blockId,
    Map<String, dynamic> payload,
  ) {
    if (blockId == null) return;
    final index = nodes.indexWhere((node) => node.id == blockId);
    if (index < 0) return;
    final node = nodes[index];
    nodes[index] = _codec.createNodeFromBlockType(
      nodeId: blockId,
      type: payload['type'] as String? ?? 'paragraph',
      text: node is TextNode ? node.text : AttributedText(),
      isTaskComplete: node is TaskNode && node.isComplete,
      metadata: Map<String, dynamic>.from(node.metadata),
    );
  }

  void _setBlockMetadata(
    List<DocumentNode> nodes,
    String? blockId,
    Map<String, dynamic> payload,
  ) {
    if (blockId == null) return;
    final index = nodes.indexWhere((node) => node.id == blockId);
    final updates = payload['metadata'] as Map<String, dynamic>?;
    if (index < 0 || updates == null) return;
    nodes[index] = _withMetadata(nodes[index], updates);
  }

  void _completeTaskOccurrence(
    List<DocumentNode> nodes,
    String? blockId,
    Map<String, dynamic> payload,
  ) {
    final targetId = blockId ?? payload['taskId'] as String?;
    if (targetId == null) return;
    final index = nodes.indexWhere((node) => node.id == targetId);
    if (index < 0 || nodes[index] is! TaskNode) return;
    final scheduledAt = payload['scheduledAt'] as String?;
    if (scheduledAt == null) return;
    final node = nodes[index] as TaskNode;
    final completions = Map<String, dynamic>.from(
      node.metadata['completions'] as Map? ?? const {},
    );
    final completedAt = payload['completedAt'] as String?;
    if (completedAt != null && completedAt.isNotEmpty) {
      completions[scheduledAt] = completedAt;
    } else {
      completions.remove(scheduledAt);
    }
    nodes[index] = _withMetadata(node, {'completions': completions});
  }

  DocumentNode _withText(TextNode node, AttributedText text) {
    if (node is TaskNode) {
      return TaskNode(
        id: node.id,
        text: text,
        isComplete: node.isComplete,
        indent: node.indent,
        metadata: Map.from(node.metadata),
      );
    }
    if (node is ListItemNode) {
      return ListItemNode(
        id: node.id,
        itemType: node.type,
        text: text,
        indent: node.indent,
        metadata: Map.from(node.metadata),
      );
    }
    if (node is ParagraphNode) {
      return ParagraphNode(
        id: node.id,
        text: text,
        indent: node.indent,
        metadata: Map.from(node.metadata),
      );
    }
    return ParagraphNode(id: node.id, text: text);
  }

  DocumentNode _withMetadata(
    DocumentNode node,
    Map<String, dynamic> updates,
  ) {
    final metadata = Map<String, dynamic>.from(node.metadata);
    for (final entry in updates.entries) {
      if (entry.value == null) {
        metadata.remove(entry.key);
      } else {
        metadata[entry.key] = entry.value;
      }
    }
    _normalizeBlockType(metadata);

    if (node is TaskNode) {
      return TaskNode(
        id: node.id,
        text: node.text,
        isComplete: updates.containsKey('isCompleted')
            ? updates['isCompleted'] as bool
            : node.isComplete,
        indent: _updatedIndent(node.indent, updates),
        metadata: metadata,
      );
    }
    if (node is ParagraphNode) {
      return ParagraphNode(
        id: node.id,
        text: node.text,
        indent: _updatedIndent(node.indent, updates),
        metadata: metadata,
      );
    }
    if (node is ListItemNode) {
      return ListItemNode(
        id: node.id,
        itemType: node.type,
        text: node.text,
        indent: _updatedIndent(node.indent, updates),
        metadata: metadata,
      );
    }
    return node;
  }

  int _updatedIndent(int current, Map<String, dynamic> updates) {
    return updates.containsKey('indent')
        ? updates['indent'] as int? ?? 0
        : current;
  }

  void _normalizeBlockType(Map<String, dynamic> metadata) {
    if (!metadata.containsKey('blockType')) return;
    final value = metadata['blockType'];
    if (value is String) {
      final attribution = _codec.attributionFromName(value);
      if (attribution == null) {
        metadata.remove('blockType');
      } else {
        metadata['blockType'] = attribution;
      }
    } else if (value == null) {
      metadata.remove('blockType');
    }
  }
}

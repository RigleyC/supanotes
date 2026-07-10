import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:supanotes/core/utils/fractional_indexing.dart';
import 'package:super_editor/super_editor.dart';
import 'package:dart_crdt/dart_crdt.dart';

import 'attachment_nodes.dart';
import 'node_sync_manager.dart';
import 'note_sync_coordinator.dart';
import 'yjs_node_codec.dart';

/// Wires a [Doc] to a [MutableDocument] via [NoteSyncCoordinator].
///
/// Handles both remote→local (via YMap observation) and local→remote
/// (via [NodeSyncManager] flush callbacks and [sendUpdate]).
class YjsDocEditorBridge {
  YjsDocEditorBridge({
    required Doc doc,
    required NoteSyncCoordinator coordinator,
    required void Function(Uint8List update) sendUpdate,
  })  : _doc = doc,
        _coordinator = coordinator,
        _sendUpdate = sendUpdate {
    _nodesSub = _doc.getMap('nodes').observe((e) => _onNodesChanged());
    coordinator.onNodeFlush = onLocalFlush;
  }

  final Doc _doc;
  final NoteSyncCoordinator _coordinator;
  final void Function(Uint8List update) _sendUpdate;
  late final void Function() _nodesSub;

  bool _isFlushingLocal = false;

  void _onNodesChanged() {
    if (_isFlushingLocal) {
      dev.log('[YjsBridge] _onNodesChanged: SKIP (local flush)', name: 'YjsBridge');
      return;
    }
    final sw = Stopwatch()..start();
    final nodes = noteNodesFromDoc(_doc);
    dev.log('[YjsBridge] _onNodesChanged: ${nodes.length} nodes from YDoc, elapsed=${sw.elapsedMilliseconds}ms', name: 'YjsBridge');
    _coordinator.updateNodesIncrementally(nodes);
    dev.log('[YjsBridge] _onNodesChanged: updateNodesIncrementally done, elapsed=${sw.elapsedMilliseconds}ms', name: 'YjsBridge');
  }

  /// Called by [NoteSyncCoordinator] when local edits are flushed to SQLite.
  void onLocalFlush(List<NodeOperation> ops) {
    if (ops.isEmpty) return;
    final sw = Stopwatch()..start();
    dev.log('[YjsBridge] onLocalFlush START ops=${ops.length}', name: 'YjsBridge');

    _isFlushingLocal = true;
    try {
      final nodesMap = _doc.getMap('nodes');

      for (final op in ops) {
        switch (op) {
          case InsertOp(:final id, :final node, :final index):
            final pos = _calcPosition(index, id, nodesMap);
            _serializeNode(node, pos, id, nodesMap);
          case DeleteOp(:final id):
            nodesMap.deleteAttr(id);
          case UpdateOp(:final id, :final node):
            _serializeNode(node, null, id, nodesMap);
          case MoveOp(:final id, :final to):
            final pos = _calcPosition(to, id, nodesMap);
            _repositionNode(id, pos, nodesMap);
        }
      }

      final update = encodeStateAsUpdate(_doc);
      dev.log('[YjsBridge] onLocalFlush: sending update updateLen=${update.length} elapsed=${sw.elapsedMilliseconds}ms', name: 'YjsBridge');
      _sendUpdate(update);
    } finally {
      _isFlushingLocal = false;
    }
    dev.log('[YjsBridge] onLocalFlush DONE elapsed=${sw.elapsedMilliseconds}ms', name: 'YjsBridge');
  }

  void _serializeNode(
    DocumentNode node,
    String? position,
    String id,
    SharedType nodesMap,
  ) {
    final dataStr = NodeSyncManager.nodeData(node);
    final data = jsonDecode(dataStr) as Map<String, dynamic>;

    if (position == null) {
      final existing = _readPosition(id, nodesMap);
      position = existing ?? 'a0';
    }

    final existingRaw = nodesMap.getAttr(id);
    final createdAt = _readCreatedAt(existingRaw) ??
        DateTime.now().millisecondsSinceEpoch.toDouble();
    final parentId = _readParentId(existingRaw) ?? '';

    final meta = <String, dynamic>{
      'id': id,
      'parentId': parentId,
      'position': position,
      'type': _attributionFor(node),
      'data': data,
      'createdAt': createdAt,
    };

    nodesMap.setAttr(id, jsonEncode(meta));

    final text = data['text'] as String?;
    final ytext = _doc.getText('content/$id');
    _updateYTextIncrementally(ytext, text ?? '');
    dev.log('[YjsBridge] _serializeNode: id=$id type=${_attributionFor(node)} position=$position textLen=${text?.length ?? 0}', name: 'YjsBridge');
  }

  void _updateYTextIncrementally(SharedType ytext, String newText) {
    final oldText = ytext.toPlainText();
    if (oldText == newText) return;

    int start = 0;
    int oldEnd = oldText.length;
    int newEnd = newText.length;

    while (start < oldEnd && start < newEnd && oldText.codeUnitAt(start) == newText.codeUnitAt(start)) {
      start++;
    }

    while (oldEnd > start && newEnd > start && oldText.codeUnitAt(oldEnd - 1) == newText.codeUnitAt(newEnd - 1)) {
      oldEnd--;
      newEnd--;
    }

    final deleteLen = oldEnd - start;
    if (deleteLen > 0) {
      ytext.deleteText(start, deleteLen);
    }

    if (newEnd > start) {
      final insertText = newText.substring(start, newEnd);
      ytext.insertText(start, insertText);
    }
  }

  String _calcPosition(int targetIndex, String? ignoreId, SharedType nodesMap) {
    final positions = <String, String>{};
    for (final key in nodesMap.attrKeys) {
      if (key == ignoreId) continue;
      final raw = nodesMap.getAttr(key);
      if (raw != null) {
        try {
          final meta = jsonDecode(raw as String) as Map<String, dynamic>;
          final pos = meta['position']?.toString() ?? '';
          positions[key] = pos;
        } catch (_) {}
      }
    }

    final sortedKeys = positions.keys.toList()
      ..sort((a, b) => positions[a]!.compareTo(positions[b]!));

    final prevKey = targetIndex > 0 && targetIndex - 1 < sortedKeys.length
        ? sortedKeys[targetIndex - 1]
        : null;
    final nextKey = targetIndex >= 0 && targetIndex < sortedKeys.length
        ? sortedKeys[targetIndex]
        : null;

    final prevPos = prevKey != null ? positions[prevKey] : null;
    final nextPos = nextKey != null ? positions[nextKey] : null;

    return FractionalIndex.between(prevPos, nextPos);
  }

  String? _readCreatedAt(dynamic raw) {
    if (raw is! String) return null;
    try {
      final meta = jsonDecode(raw) as Map<String, dynamic>;
      final ca = meta['createdAt'] as num?;
      return ca?.toString();
    } catch (_) {
      return null;
    }
  }

  String? _readParentId(dynamic raw) {
    if (raw is! String) return null;
    try {
      final meta = jsonDecode(raw) as Map<String, dynamic>;
      return meta['parentId'] as String?;
    } catch (_) {
      return null;
    }
  }

  void _repositionNode(String id, String position, SharedType nodesMap) {
    final raw = nodesMap.getAttr(id);
    if (raw == null) return;
    try {
      final meta = jsonDecode(raw as String) as Map<String, dynamic>;
      meta['position'] = position;
      nodesMap.setAttr(id, jsonEncode(meta));
    } catch (_) {}
  }

  String? _readPosition(String id, SharedType nodesMap) {
    final raw = nodesMap.getAttr(id);
    if (raw == null) return null;
    try {
      final meta = jsonDecode(raw as String) as Map<String, dynamic>;
      return meta['position']?.toString();
    } catch (_) {
      return null;
    }
  }

  String _attributionFor(DocumentNode node) {
    if (node is ParagraphNode) {
      final blockType = node.getMetadataValue('blockType') as Attribution?;
      if (blockType == null) return 'paragraph';
      if (blockType == blockquoteAttribution) return 'blockquote';
      if (blockType.id.startsWith('header')) return 'header';
      return 'paragraph';
    }
    if (node is TaskNode) return 'task';
    if (node is ListItemNode) return 'list_item';
    if (node is HorizontalRuleNode) return 'divider';
    if (node is ImageNode) return 'image';
    if (node is DocumentAttachmentNode) return 'attachment';
    return 'paragraph';
  }

  void dispose() {
    _nodesSub();
    _coordinator.onNodeFlush = null;
  }
}

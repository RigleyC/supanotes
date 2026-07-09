import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:super_editor/super_editor.dart';
import 'package:yjs_dart/yjs_dart.dart';

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
    _nodesSub = _doc.getMap('nodes')!.observe(_onNodesChanged);
    coordinator.onNodeFlush = onLocalFlush;
  }

  final Doc _doc;
  final NoteSyncCoordinator _coordinator;
  final void Function(Uint8List update) _sendUpdate;
  late final void Function(dynamic, Transaction) _nodesSub;

  bool _isFlushingLocal = false;

  void _onNodesChanged(dynamic event, Transaction tr) {
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
      final nodesMap = _doc.getMap('nodes')!;

      for (final op in ops) {
        switch (op) {
          case InsertOp(:final id, :final node, :final index):
            _serializeNode(node, index.toDouble(), id, nodesMap);
          case DeleteOp(:final id):
            nodesMap.delete(id);
          case UpdateOp(:final id, :final node):
            _serializeNode(node, null, id, nodesMap);
          case MoveOp(:final id, :final to):
            _repositionNode(id, to.toDouble(), nodesMap);
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
    double? position,
    String id,
    YMap nodesMap,
  ) {
    final dataStr = NodeSyncManager.nodeData(node);
    final data = jsonDecode(dataStr) as Map<String, dynamic>;

    if (position == null) {
      final existing = _readPosition(id, nodesMap);
      position = existing ?? 0.0;
    }

    final existingRaw = nodesMap.get(id);
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

    nodesMap.set(id, jsonEncode(meta));

    final text = data['text'] as String?;
    final ytext = _doc.getText('content/$id')!;
    _updateYTextIncrementally(ytext, text ?? '');
    dev.log('[YjsBridge] _serializeNode: id=$id type=${_attributionFor(node)} position=$position textLen=${text?.length ?? 0}', name: 'YjsBridge');
  }

  void _updateYTextIncrementally(YText ytext, String newText) {
    final oldText = ytext.toString();
    if (oldText == newText) return;

    final oldRunes = oldText.runes.toList();
    final newRunes = newText.runes.toList();

    int start = 0;
    int oldEnd = oldRunes.length;
    int newEnd = newRunes.length;

    // Find common prefix
    while (start < oldEnd && start < newEnd && oldRunes[start] == newRunes[start]) {
      start++;
    }

    // Find common suffix
    while (oldEnd > start && newEnd > start && oldRunes[oldEnd - 1] == newRunes[newEnd - 1]) {
      oldEnd--;
      newEnd--;
    }

    // Delete deleted characters
    final deleteLen = oldEnd - start;
    if (deleteLen > 0) {
      ytext.delete(start, deleteLen);
    }

    // Insert inserted characters
    if (newEnd > start) {
      final insertText = String.fromCharCodes(newRunes.sublist(start, newEnd));
      ytext.insert(start, insertText);
    }
  }

  double? _readCreatedAt(dynamic raw) {
    if (raw is! String) return null;
    try {
      final meta = jsonDecode(raw) as Map<String, dynamic>;
      final ca = meta['createdAt'] as num?;
      return ca?.toDouble();
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

  void _repositionNode(String id, double position, YMap nodesMap) {
    final raw = nodesMap.get(id);
    if (raw == null) return;
    try {
      final meta = jsonDecode(raw as String) as Map<String, dynamic>;
      meta['position'] = position;
      nodesMap.set(id, jsonEncode(meta));
    } catch (_) {}
  }

  double? _readPosition(String id, YMap nodesMap) {
    final raw = nodesMap.get(id);
    if (raw == null) return null;
    try {
      final meta = jsonDecode(raw as String) as Map<String, dynamic>;
      return (meta['position'] as num?)?.toDouble();
    } catch (_) {
      return null;
    }
  }

  String _attributionFor(DocumentNode node) {
    if (node is ParagraphNode) {
      final blockType = node.getMetadataValue('blockType') as Attribution?;
      if (blockType == null) return 'paragraph';
      if (blockType == blockquoteAttribution) return 'blockquote';
      return 'header';
    }
    if (node is TaskNode) return 'task';
    if (node is ListItemNode) return 'list_item';
    if (node is HorizontalRuleNode) return 'divider';
    if (node is ImageNode) return 'image';
    if (node is DocumentAttachmentNode) return 'attachment';
    return 'paragraph';
  }

  void dispose() {
    _doc.getMap('nodes')?.unobserve(_nodesSub);
    _coordinator.onNodeFlush = null;
  }
}

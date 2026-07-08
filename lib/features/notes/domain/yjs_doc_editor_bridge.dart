import 'dart:convert';
import 'dart:typed_data';

import 'package:yjs_dart/yjs_dart.dart';

import '../../../core/database/database.dart';
import 'note_sync_coordinator.dart';

/// Wires a [Doc] to a [MutableDocument] via [NoteSyncCoordinator].
class YjsDocEditorBridge {
  YjsDocEditorBridge({
    required Doc doc,
    required NoteSyncCoordinator coordinator,
    required void Function(Uint8List update) sendUpdate,
  })  : _doc = doc,
        _coordinator = coordinator,
        _sendUpdate = sendUpdate {
    _nodesSub = _doc.getMap('nodes')!.observe(_onNodesChanged);
  }

  final Doc _doc;
  final NoteSyncCoordinator _coordinator;
  final void Function(Uint8List update) _sendUpdate;
  late final void Function(dynamic, Transaction) _nodesSub;

  void _onNodesChanged(dynamic event, Transaction tr) {
    final nodes = <NoteNode>[];
    final nodesMap = _doc.getMap('nodes');
    if (nodesMap == null) return;

    for (final key in nodesMap.keys) {
      final raw = nodesMap.get(key);
      if (raw is! String) continue;
      try {
        final meta = jsonDecode(raw) as Map<String, dynamic>;
        final nodeId = meta['id'] as String;
        final ytext = _doc.getText('content/$nodeId');
        final textContent = ytext?.toString() ?? '';
        final data = Map<String, dynamic>.from(meta['data'] as Map? ?? {});
        if (textContent.isNotEmpty) {
          data['text'] = textContent;
        }
        final dataStr = jsonEncode(data);
        nodes.add(NoteNode(
          id: nodeId,
          noteId: meta['noteId'] as String? ?? '',
          parentId: (meta['parentId'] as String?)?.isEmpty == true
              ? null
              : meta['parentId'] as String?,
          position: (meta['position'] as num?)?.toDouble() ?? 0.0,
          type: meta['type'] as String? ?? 'paragraph',
          data: dataStr,
          createdAt:
              DateTime.fromMillisecondsSinceEpoch((meta['createdAt'] as num?)?.toInt() ?? 0),
          updatedAt:
              DateTime.fromMillisecondsSinceEpoch((meta['updatedAt'] as num?)?.toInt() ?? 0),
          isDirty: false,
        ));
      } catch (_) {
        continue;
      }
    }

    nodes.sort((a, b) => a.position.compareTo(b.position));
    _coordinator.updateNodesIncrementally(nodes);
  }

  void onLocalEdit(Uint8List update) {
    _sendUpdate(update);
  }

  void dispose() {
    _doc.getMap('nodes')?.unobserve(_nodesSub);
  }
}

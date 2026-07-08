import 'package:yjs_dart/yjs_dart.dart';

import 'note_sync_coordinator.dart';
import 'yjs_node_codec.dart';

/// Wires a [Doc] to a [MutableDocument] via [NoteSyncCoordinator].
class YjsDocEditorBridge {
  YjsDocEditorBridge({
    required Doc doc,
    required NoteSyncCoordinator coordinator,
  })  : _doc = doc,
        _coordinator = coordinator {
    _nodesSub = _doc.getMap('nodes')!.observe(_onNodesChanged);
  }

  final Doc _doc;
  final NoteSyncCoordinator _coordinator;
  late final void Function(dynamic, Transaction) _nodesSub;

  void _onNodesChanged(dynamic event, Transaction tr) {
    final nodes = noteNodesFromDoc(_doc);
    _coordinator.updateNodesIncrementally(nodes);
  }

  void dispose() {
    _doc.getMap('nodes')?.unobserve(_nodesSub);
  }
}

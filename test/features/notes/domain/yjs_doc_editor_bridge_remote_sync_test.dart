import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'package:supanotes/features/notes/domain/editor_document_sync_manager.dart';
import 'package:supanotes/features/notes/domain/yjs_doc_editor_bridge.dart';

void main() {
  test('a remote single-node update preserves unchanged nodes', () async {
    final source = Doc();
    final sourceNodes = source.getMap<Object>('nodes')!;
    source.transact((_) {
      for (final id in ['t1', 't2']) {
        final node = YMap<Object>();
        node.set('id', id);
        node.set('type', 'task');
        node.set('position', id == 't1' ? 'a0' : 'a1');
        node.set('data', jsonEncode({'text': id, 'completed': false}));
        sourceNodes.set(id, node);
      }
    });

    final replica = Doc();
    applyUpdate(replica, encodeStateAsUpdate(source));
    final document = MutableDocument(
      nodes: [
        TaskNode(id: 't1', text: AttributedText('t1'), isComplete: false),
        TaskNode(id: 't2', text: AttributedText('t2'), isComplete: false),
      ],
    );
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: MutableDocumentComposer(),
    )..reactionPipeline.clear();
    final coordinator = EditorDocumentSyncManager(
      document: document,
      editor: editor,
    );
    final bridge = YjsDocEditorBridge(
      doc: replica,
      userId: 'test-user',
      coordinator: coordinator,
    );
    await Future<void>.delayed(Duration.zero);

    source.transact((_) {
      (sourceNodes.get('t1') as YMap).set('completed', true);
    });
    applyUpdate(replica, encodeStateAsUpdate(source));
    await Future<void>.delayed(Duration.zero);

    expect(document.map((node) => node.id), ['t1', 't2']);

    source.transact((_) {
      sourceNodes.delete('t1');
      sourceNodes.delete('t2');
    });
    applyUpdate(replica, encodeStateAsUpdate(source));
    await Future<void>.delayed(Duration.zero);

    expect(document, isEmpty);

    bridge.dispose();
    await coordinator.dispose();
  });
}

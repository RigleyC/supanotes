import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'package:supanotes/features/notes/domain/editor_document_sync_manager.dart';
import 'package:supanotes/features/notes/domain/yjs_doc_editor_bridge.dart';

void main() {
  test('Marking task on second device does not uncheck previous tasks', () async {
    // 1. Create a document with 3 tasks
    final doc1 = Doc();
    doc1.getMap<Object>('nodes');
    final document1 = MutableDocument(nodes: [
      TaskNode(id: 't1', text: AttributedText('Task 1'), isComplete: false),
      TaskNode(id: 't2', text: AttributedText('Task 2'), isComplete: false),
      TaskNode(id: 't3', text: AttributedText('Task 3'), isComplete: false),
    ]);
    final composer1 = MutableDocumentComposer();
    final editor1 = createDefaultDocumentEditor(
      document: document1,
      composer: composer1,
    )..reactionPipeline.clear();
    final coord1 = EditorDocumentSyncManager(document: document1, editor: editor1);
    final bridge1 = YjsDocEditorBridge(
      doc: doc1,
      userId: 'test-user',
      coordinator: coord1,
      sendUpdate: (_) {},
      onDocChanged: () {},
    );
    // Seed initial nodes into YDoc
    doc1.transact((txn) {
      final nodesMap = doc1.getMap<Object>('nodes')!;
      final ids = ['t1', 't2', 't3'];
      for (int i = 0; i < ids.length; i++) {
        final ym = YMap<Object>();
        ym.set('id', ids[i]);
        ym.set('type', 'task');
        ym.set('position', 'a$i');
        ym.set('data', '{}');
        ym.set('createdAt', 1000.0);
        ym.set('completed', false);
        nodesMap.set(ids[i], ym);
      }
    });
    await coord1.flushNow();

    // 2. Mark T1 and T2 as complete on Device 1
    editor1.execute([
      ReplaceNodeRequest(
        existingNodeId: 't1',
        newNode: TaskNode(id: 't1', text: AttributedText('Task 1'), isComplete: true),
      ),
      ReplaceNodeRequest(
        existingNodeId: 't2',
        newNode: TaskNode(id: 't2', text: AttributedText('Task 2'), isComplete: true),
      ),
    ]);
    await coord1.flushNow();

    // Verify they are checked in doc1
    final nodesMap1 = doc1.getMap<Object>('nodes')!;
    expect((nodesMap1.get('t1') as YMap).get('completed'), isTrue);
    expect((nodesMap1.get('t2') as YMap).get('completed'), isTrue);

    // 3. Serialize doc1 to update and load into doc2
    final updateBytes = encodeStateAsUpdate(doc1);
    final doc2 = Doc();
    doc2.getMap<Object>('nodes');
    applyUpdate(doc2, updateBytes);

    // 4. Initialize Device 2
    final document2 = MutableDocument(nodes: [
      TaskNode(id: 't1', text: AttributedText('Task 1'), isComplete: true),
      TaskNode(id: 't2', text: AttributedText('Task 2'), isComplete: true),
      TaskNode(id: 't3', text: AttributedText('Task 3'), isComplete: false),
    ]);
    final composer2 = MutableDocumentComposer();
    final editor2 = createDefaultDocumentEditor(
      document: document2,
      composer: composer2,
    )..reactionPipeline.clear();
    final coord2 = EditorDocumentSyncManager(document: document2, editor: editor2);
    final bridge2 = YjsDocEditorBridge(
      doc: doc2,
      userId: 'test-user',
      coordinator: coord2,
      sendUpdate: (_) {},
      onDocChanged: () {},
    );

    // 5. Mark T3 as complete on Device 2
    editor2.execute([
      ReplaceNodeRequest(
        existingNodeId: 't3',
        newNode: TaskNode(id: 't3', text: AttributedText('Task 3'), isComplete: true),
      ),
    ]);
    await coord2.flushNow();

    // 6. Verify T1 and T2 are STILL complete on Device 2
    final t1 = document2.getNodeById('t1') as TaskNode;
    final t2 = document2.getNodeById('t2') as TaskNode;
    expect(t1.isComplete, true);
    expect(t2.isComplete, true);
  });
}

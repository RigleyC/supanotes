import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'package:supanotes/features/notes/domain/editor_document_sync_manager.dart';
import 'package:supanotes/features/notes/domain/yjs_doc_editor_bridge.dart';
import 'package:supanotes/core/sync/yjs_sync_manager.dart';

void main() {
  test('Task order bug reproduction', () async {
    // 1. Create a document on Device 1
    final doc1 = Doc();
    final nodesMap1 = doc1.getMap<Object>('nodes')!;
    
    // Seed the initial node in doc1 before the bridge is created
    doc1.transact((txn) {
      final nodeMap = YMap<Object>();
      nodeMap.set('id', 't1');
      nodeMap.set('position', 'a0');
      nodeMap.set('type', 'task');
      nodeMap.set('data', jsonEncode({
        'text': 'Task 1',
        'completed': false,
      }));
      nodesMap1.set('t1', nodeMap);
    });

    final document1 = MutableDocument(nodes: [
      TaskNode(id: 't1', text: AttributedText('Task 1'), isComplete: false),
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
      onDocChanged: () {},
    );
    await coord1.flushNow();

    // Serialize from Device 1
    final update1 = encodeStateAsUpdate(doc1);

    // 2. Load on Device 2
    final doc2 = Doc();
    applyUpdate(doc2, update1);
    final document2 = MutableDocument(nodes: [
      TaskNode(id: 't1', text: AttributedText('Task 1'), isComplete: false),
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
      onDocChanged: () {},
    );

    // Device 2 inserts a new task below t1 using editor command
    editor2.execute([
      InsertNodeAtIndexRequest(
        nodeIndex: 1,
        newNode: TaskNode(
          id: 't2',
          text: AttributedText('Task 2'),
          isComplete: false,
        ),
      ),
    ]);
    await coord2.flushNow();

    final nodesMap2 = doc2.getMap<Object>('nodes')!;
    final node1 = nodesMap2.get('t1') as YMap;
    final node2 = nodesMap2.get('t2') as YMap;
    final pos1 = node1.get('position') as String;
    final pos2 = node2.get('position') as String;

    print('Device 2 Task 1 position: $pos1');
    print('Device 2 Task 2 position: $pos2');

    expect(pos2.compareTo(pos1) > 0, isTrue, reason: 'Task 2 should come AFTER Task 1');
  });
}

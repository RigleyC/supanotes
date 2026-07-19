import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'package:supanotes/features/notes/domain/editor_document_sync_manager.dart';
import 'package:supanotes/features/notes/domain/yjs_doc_editor_bridge.dart';

void main() {
  test('Fuzzing YjsDocEditorBridge and NodeSyncManager with random operations', () async {
    final random = Random(42);
    
    // 1. Initialize Document and Editor
    final doc = Doc();
    doc.getMap<Object>('nodes');
    
    final document = MutableDocument(nodes: [
      ParagraphNode(id: 'p1', text: AttributedText('Initial text')),
    ]);
    final composer = MutableDocumentComposer();
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    )..reactionPipeline.clear();
    
    final coord = EditorDocumentSyncManager(document: document, editor: editor);
    final bridge = YjsDocEditorBridge(
      doc: doc,
      userId: 'test-user',
      coordinator: coord,
      onDocChanged: ({required isRemote}) {},
    );
    
    // Initial flush
    await coord.flushNow();
    
    // Create a remote doc to simulate incoming WS messages
    final remoteDoc = Doc();
    remoteDoc.getMap<Object>('nodes');
    applyUpdate(remoteDoc, encodeStateAsUpdate(doc));
    
    int remoteNodeCounter = 100;
    
    // 2. Perform N random operations
    for (int i = 0; i < 50; i++) {
      final opType = random.nextInt(4);
      
      switch (opType) {
        case 0: // Local insert
          final nodeCount = document.nodeCount;
          final insertIndex = random.nextInt(nodeCount + 1);
          final newNodeId = 'local_${i}';
          
          editor.execute([
            InsertNodeAtIndexRequest(
              nodeIndex: insertIndex,
              newNode: TaskNode(
                id: newNodeId,
                text: AttributedText('Local task $i'),
                isComplete: false,
              ),
            ),
          ]);
          break;
          
        case 1: // Local toggle task
          final taskNodes = document.toList().whereType<TaskNode>().toList();
          if (taskNodes.isNotEmpty) {
            final target = taskNodes[random.nextInt(taskNodes.length)];
            editor.execute([
              ReplaceNodeRequest(
                existingNodeId: target.id,
                newNode: target.copyTaskWith(isComplete: !target.isComplete),
              ),
            ]);
          }
          break;
          
        case 2: // Local edit text
          final pNodes = document.toList().whereType<TextNode>().toList();
          if (pNodes.isNotEmpty) {
            final target = pNodes[random.nextInt(pNodes.length)];
            final newText = AttributedText('${target.text.toPlainText()} appended');
            editor.execute([
              ReplaceNodeRequest(
                existingNodeId: target.id,
                newNode: ParagraphNode(id: target.id, text: newText),
              ),
            ]);
          }
          break;
          
        case 3: // Remote update via YDoc (simulating WebSocket)
          remoteDoc.transact((txn) {
            final rNodes = remoteDoc.getMap<Object>('nodes')!;
            final rId = 'remote_${remoteNodeCounter++}';
            
            final rMap = YMap<Object>();
            rMap.set('id', rId);
            rMap.set('type', 'paragraph');
            rMap.set('position', 'z$remoteNodeCounter');
            rMap.set('data', jsonEncode({'text': 'Remote generated node'}));
            rMap.set('createdAt', DateTime.now().millisecondsSinceEpoch.toDouble());
            
            rNodes.set(rId, rMap);
            
            // create YText
            remoteDoc.getText('content/$rId')!.insert(0, 'Remote generated node');
          });
          
          final updateBytes = encodeStateAsUpdate(remoteDoc);
          // Apply to local doc, triggering observer -> _onNodesChanged -> incremental update
          applyUpdate(doc, updateBytes);
          break;
      }
      
      // Randomly flush local changes
      if (random.nextDouble() > 0.5) {
        await coord.flushNow();
      }
    }
    
    // Final flush
    await coord.flushNow();
    
    // 3. Verify consistency
    // Every node in MutableDocument should exist in YDoc and match text/status
    final nodesMap = doc.getMap<Object>('nodes')!;
    
    for (final node in document.toList()) {
      final yRaw = nodesMap.get(node.id);
      expect(yRaw, isNotNull, reason: 'Node ${node.id} missing from YDoc');
      expect(yRaw is YMap, isTrue, reason: 'Node ${node.id} is not a YMap');
      
      final yMap = yRaw as YMap;
      if (node is TextNode) {
        final yText = doc.getText('content/${node.id}');
        expect(yText.toString(), node.text.toPlainText(), reason: 'Text mismatch for ${node.id}');
      }
      if (node is TaskNode) {
        final yCompleted = yMap.get('completed') as bool?;
        expect(yCompleted, node.isComplete, reason: 'Task status mismatch for ${node.id}');
      }
    }
  });
}

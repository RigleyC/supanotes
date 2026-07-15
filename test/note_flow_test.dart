import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:yjs_dart/yjs_dart.dart';
import 'package:supanotes/features/notes/domain/yjs_doc_editor_bridge.dart';
import 'package:supanotes/features/notes/domain/node_sync_manager.dart';
import 'package:supanotes/features/notes/domain/note_sync_coordinator.dart';

void main() {
  test('Local flush and reload', () async {
    final doc = Doc();
    
    // 1. Initialize editor with empty doc
    final document = MutableDocument(nodes: [
      ParagraphNode(id: 'node1', text: AttributedText('')),
    ]);
    final composer = MutableDocumentComposer();
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    )..reactionPipeline.clear();
    
    final coordinator = NoteSyncCoordinator(document: document, editor: editor);
    final bridge = YjsDocEditorBridge(
      doc: doc,
      coordinator: coordinator,
      sendUpdate: (_) {},
      onDocChanged: () {},
    );
    
    // 2. Simulate user typing via editor
    editor.execute([
      ReplaceNodeRequest(
        existingNodeId: 'node1',
        newNode: ParagraphNode(id: 'node1', text: AttributedText('Hello World')),
      ),
    ]);
    
    // Simulate what NodeSyncManager does on text change
    bridge.onLocalFlush([
      UpdateOp('node1', document.getNodeById('node1')!),
    ]);
    
    // 3. Verify Doc has the data
    final map = doc.getMap<Object>('nodes')!;
    expect(map.keys.contains('node1'), true);
    
    final text = doc.getText('content/node1')!;
    expect(text.toString(), 'Hello World');
    
    // 4. Encode and decode — pre-register types to work around yjs_dart
    // type identity loss: Doc.get auto-creates YMap<dynamic> from binary
    // instead of preserving the original generic type parameter.
    final state = encodeStateAsUpdate(doc);
    
    final newDoc = Doc();
    newDoc.getMap<Object>('nodes');
    newDoc.getText('content/node1');
    applyUpdate(newDoc, state);
    
    final newMap = newDoc.getMap<Object>('nodes')!;
    expect(newMap.keys.contains('node1'), true, reason: 'Map should contain node1 after reload');
    
    final newText = newDoc.getText('content/node1')!;
    expect(newText.toString(), 'Hello World', reason: 'Text should be Hello World after reload');
  });
}

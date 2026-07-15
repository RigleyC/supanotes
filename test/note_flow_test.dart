import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:dart_crdt/dart_crdt.dart';
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
    final editor = Editor(editables: {
      Editor.documentKey: document,
    }, requestHandlers: []);
    
    final coordinator = NoteSyncCoordinator(document: document, editor: editor);
    final bridge = YjsDocEditorBridge(
      doc: doc,
      coordinator: coordinator,
      sendUpdate: (_) {},
      onDocChanged: () {},
    );
    
    // 2. Simulate user typing
    final node = document.getNodeById('node1') as ParagraphNode;
    node.text = AttributedText('Hello World');
    
    // Simulate what NodeSyncManager does on text change
    bridge.onLocalFlush([
      UpdateOp('node1', node),
    ]);
    
    // 3. Verify Doc has the data
    final map = doc.getMap('nodes');
    expect(map.attrKeys.contains('node1'), true);
    
    final text = doc.getText('content/node1');
    expect(text.toPlainText(), 'Hello World');
    
    // 4. Encode and decode
    final state = encodeStateAsUpdate(doc);
    
    final newDoc = Doc();
    applyUpdate(newDoc, state);
    
    final newMap = newDoc.getMap('nodes');
    expect(newMap.attrKeys.contains('node1'), true, reason: 'Map should contain node1 after reload');
    
    final newText = newDoc.getText('content/node1');
    expect(newText.toPlainText(), 'Hello World', reason: 'Text should be Hello World after reload');
  });
}

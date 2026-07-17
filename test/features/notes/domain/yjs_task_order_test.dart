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
    doc1.getMap<Object>('nodes');
    doc1.getMap<String>('tasks');
    final document1 = MutableDocument(nodes: [
      TaskNode(id: 't1', text: AttributedText('Task 1'), isComplete: false),
    ]);
    final editor1 = Editor(editables: {
      Editor.documentKey: document1,
    });
    final coord1 = EditorDocumentSyncManager(document: document1, editor: editor1);
    final bridge1 = YjsDocEditorBridge(
      doc: doc1,
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
    final editor2 = Editor(editables: {
      Editor.documentKey: document2,
    });
    final coord2 = EditorDocumentSyncManager(document: document2, editor: editor2);
    final bridge2 = YjsDocEditorBridge(
      doc: doc2,
      coordinator: coord2,
      onDocChanged: () {},
    );

    // Device 2 inserts a new task below t1
    editor2.context.document.insertNodeAt(
      1,
      TaskNode(
        id: 't2',
        text: AttributedText('Task 2'),
        isComplete: false,
      ),
    );
    await coord2.flushNow();

    final nodesMap2 = doc2.getMap<Object>('nodes')!;
    final pos1 = jsonDecode(nodesMap2.get('t1') as String)['position'];
    final pos2 = jsonDecode(nodesMap2.get('t2') as String)['position'];

    print('Device 2 Task 1 position: $pos1');
    print('Device 2 Task 2 position: $pos2');

    expect(pos2.compareTo(pos1) > 0, isTrue, reason: 'Task 2 should come AFTER Task 1');
  });
}

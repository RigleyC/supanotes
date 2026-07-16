import 'dart:convert';
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
    doc1.getMap<String>('tasks');
    final document1 = MutableDocument(nodes: [
      TaskNode(id: 't1', text: AttributedText('Task 1'), isComplete: false),
      TaskNode(id: 't2', text: AttributedText('Task 2'), isComplete: false),
      TaskNode(id: 't3', text: AttributedText('Task 3'), isComplete: false),
    ]);
    final editor1 = Editor(editables: {
      Editor.documentKey: document1,
    }, requestHandlers: [
      (editor, request) {
        if (request is ChangeTaskCompletionRequest) {
          final taskNode = document1.getNodeById(request.nodeId) as TaskNode;
          document1.replaceNodeById(taskNode.id, taskNode.copyTaskWith(isComplete: request.isComplete));
          return ChangeTaskCompletionCommand(nodeId: request.nodeId, isComplete: request.isComplete);
        }
        return null;
      }
    ]);
    final coord1 = EditorDocumentSyncManager(document: document1, editor: editor1);
    final bridge1 = YjsDocEditorBridge(
      doc: doc1,
      coordinator: coord1,
      sendUpdate: (_) {},
      onDocChanged: () {},
    );
    // Flush initial state to doc1
    await coord1.flushNow();

    // 2. Mark T1 and T2 as complete on Device 1
    editor1.execute([
      ChangeTaskCompletionRequest(nodeId: 't1', isComplete: true),
      ChangeTaskCompletionRequest(nodeId: 't2', isComplete: true),
    ]);
    await coord1.flushNow();

    // Verify they are checked in doc1
    final tasksMap1 = doc1.getMap('tasks')!;
    expect(jsonDecode(tasksMap1.get('t1'))['completed'], true);
    expect(jsonDecode(tasksMap1.get('t2'))['completed'], true);

    // 3. Serialize doc1 to update and load into doc2
    final updateBytes = encodeStateAsUpdate(doc1);
    final doc2 = Doc();
    doc2.getMap<Object>('nodes');
    doc2.getMap<String>('tasks');
    applyUpdate(doc2, updateBytes); // applyUpdate, not applyUpdateSafe

    // 4. Initialize Device 2
    // Simulate initFromDoc
    final document2 = MutableDocument(nodes: [
      TaskNode(id: 't1', text: AttributedText('Task 1'), isComplete: true), // it would parse as true
      TaskNode(id: 't2', text: AttributedText('Task 2'), isComplete: true),
      TaskNode(id: 't3', text: AttributedText('Task 3'), isComplete: false),
    ]);
    final editor2 = Editor(editables: {
      Editor.documentKey: document2,
    }, requestHandlers: [
      (editor, request) {
        if (request is ChangeTaskCompletionRequest) {
          final taskNode = document2.getNodeById(request.nodeId) as TaskNode;
          document2.replaceNodeById(taskNode.id, taskNode.copyTaskWith(isComplete: request.isComplete));
          return ChangeTaskCompletionCommand(nodeId: request.nodeId, isComplete: request.isComplete);
        }
        return null;
      }
    ]);
    final coord2 = EditorDocumentSyncManager(document: document2, editor: editor2);
    final bridge2 = YjsDocEditorBridge(
      doc: doc2,
      coordinator: coord2,
      sendUpdate: (_) {},
      onDocChanged: () {},
    );

    // 5. Mark T3 as complete on Device 2
    editor2.execute([
      ChangeTaskCompletionRequest(nodeId: 't3', isComplete: true),
    ]);
    await coord2.flushNow();

    // 6. Verify T1 and T2 are STILL complete on Device 2
    final t1 = document2.getNodeById('t1') as TaskNode;
    final t2 = document2.getNodeById('t2') as TaskNode;
    expect(t1.isComplete, true);
    expect(t2.isComplete, true);
  });
}

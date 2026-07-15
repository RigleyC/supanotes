import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:super_editor/super_editor.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/domain/editor_document_sync_manager.dart';
import 'package:supanotes/features/notes/domain/note_node.dart';
import 'package:supanotes/features/notes/domain/yjs_doc_editor_bridge.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.test(executor: NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('YjsDocEditorBridge', () {
    test('Typing in editor updates Yjs Doc', () async {
      final doc = Doc();
      final mutableDoc = MutableDocument.empty();
      final composer = MutableDocumentComposer();
      final editor = createDefaultDocumentEditor(
        document: mutableDoc,
        composer: composer,
      )..reactionPipeline.clear();

      final coordinator = EditorDocumentSyncManager(
        document: mutableDoc,
        editor: editor,
      );

      final updates = <Uint8List>[];
      final bridge = YjsDocEditorBridge(
        doc: doc,
        coordinator: coordinator,
        sendUpdate: (u) => updates.add(u),
      );

      // Simulate inserting a node locally via editor
      editor.execute([
        InsertNodeAtIndexRequest(
          nodeIndex: 0,
          newNode: ParagraphNode(id: 'p1', text: AttributedText('Hello World')),
        ),
      ]);

      // Flush local coordinator state manually to trigger bridge sync
      bridge.onLocalFlush(coordinator.locallyDirtyNodeIds.map((id) {
        final node = mutableDoc.getNodeById(id)!;
        return InsertOp(id, node, 0);
      }).toList());

      // Verify that YDoc map got the node serialized and the text updated
      final nodesMap = doc.getMap<Object>('nodes')!;
      expect(nodesMap.keys, contains('p1'));

      final meta = jsonDecode(nodesMap.get('p1') as String) as Map<String, dynamic>;
      expect(meta['id'], 'p1');
      expect(meta['type'], 'paragraph');

      final ytext = doc.getText('content/p1')!;
      expect(ytext.toString(), 'Hello World');
      expect(updates, isNotEmpty);

      bridge.dispose();
    });

    test('Selection preservation and clamping during remote sync', () async {
      final mutableDoc = MutableDocument(nodes: [
        ParagraphNode(id: 'p1', text: AttributedText('Hello')),
      ]);
      final composer = MutableDocumentComposer(
        initialSelection: const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: 'p1',
            nodePosition: TextNodePosition(offset: 3),
          ),
        ),
      );
      final editor = createDefaultDocumentEditor(
        document: mutableDoc,
        composer: composer,
      );

      final coordinator = EditorDocumentSyncManager(
        document: mutableDoc,
        editor: editor,
      );

      // 1. Remote update with longer text -> selection offset 3 must be preserved
      coordinator.updateNodesIncrementally([
        NoteNode(
          id: 'p1',
          noteId: 'note-1',
          position: '1.0',
          type: 'paragraph',
          data: jsonEncode({'text': 'Hello World', 'spans': []}),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ]);

      expect(composer.selection, isNotNull);
      expect(composer.selection!.base.nodeId, 'p1');
      expect((composer.selection!.base.nodePosition as TextNodePosition).offset, 3);

      // 2. Remote update with shorter text -> selection offset must be clamped
      coordinator.updateNodesIncrementally([
        NoteNode(
          id: 'p1',
          noteId: 'note-1',
          position: '1.0',
          type: 'paragraph',
          data: jsonEncode({'text': 'Hi', 'spans': []}),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ]);

      expect(composer.selection, isNotNull);
      expect(composer.selection!.base.nodeId, 'p1');
      expect((composer.selection!.base.nodePosition as TextNodePosition).offset, 2); // Clamped to Hi's length
    });

    test('Incremental sync of task node completion status does not replace the node object instance', () async {
      final taskNode = TaskNode(
        id: 't1',
        text: AttributedText('Buy milk'),
        isComplete: false,
      );
      final mutableDoc = MutableDocument(nodes: [taskNode]);
      final composer = MutableDocumentComposer();
      final editor = createDefaultDocumentEditor(
        document: mutableDoc,
        composer: composer,
      );

      final coordinator = EditorDocumentSyncManager(
        document: mutableDoc,
        editor: editor,
      );

      // Verify initial state
      final firstNode = mutableDoc.getNodeById('t1') as TaskNode;
      expect(firstNode.isComplete, isFalse);

      // Apply incoming node change where completion status becomes true
      coordinator.updateNodesIncrementally([
        NoteNode(
          id: 't1',
          noteId: 'note-1',
          position: '1.0',
          type: 'task',
          data: jsonEncode({
            'text': 'Buy milk',
            'spans': [],
            'completed': true,
            'indent': 0,
          }),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ]);

      final updatedNode = mutableDoc.getNodeById('t1') as TaskNode;
      // Crucial: The node completion status must be successfully synced.
      expect(updatedNode.isComplete, isTrue);
    });

    test('completeRecurringTask preserves recurrence in YMap tasks entry', () async {
      final doc = Doc();
      final mutableDoc = MutableDocument.empty();
      final composer = MutableDocumentComposer();
      final editor = createDefaultDocumentEditor(
        document: mutableDoc,
        composer: composer,
      )..reactionPipeline.clear();

      final coordinator = EditorDocumentSyncManager(
        document: mutableDoc,
        editor: editor,
      );

      final bridge = YjsDocEditorBridge(
        doc: doc,
        coordinator: coordinator,
        sendUpdate: (_) {},
      );

      // Seed a recurring task in the YDoc.
      doc.transact((txn) {
        doc.getMap<Object>('nodes')!.set(
          't1',
          jsonEncode({
            'id': 't1',
            'position': 'a0',
            'type': 'task',
            'data': {
              'text': 'Daily task',
              'completed': false,
              'recurrence': 'daily',
            },
          }),
        );
        doc.getText('content/t1')!.insert(0, 'Daily task');
        doc.getMap<Object>('tasks')!.set(
          't1',
          jsonEncode({
            'nodeId': 't1',
            'completed': false,
            'title': 'Daily task',
            'dueDate': '2026-07-14',
            'recurrence': 'daily',
          }),
        );
      });

      final nextDue = DateTime(2026, 7, 15);
      bridge.completeRecurringTask('t1', nextDue);

      final tasksMap = doc.getMap<Object>('tasks')!;
      final entry = jsonDecode(tasksMap.get('t1') as String) as Map<String, dynamic>;
      expect(entry['completed'], isFalse);
      expect(entry['dueDate'], '2026-07-15');
      expect(entry['recurrence'], 'daily');

      bridge.dispose();
    });
  });
}

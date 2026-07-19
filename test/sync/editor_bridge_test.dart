import 'dart:convert';
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

      final bridge = YjsDocEditorBridge(
        doc: doc,
        userId: 'test-user',
        coordinator: coordinator,
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
        return InsertOp(id, node, null, null);
      }).toList());

      // Verify that YDoc map got the node serialized and the text updated
      final nodesMap = doc.getMap<Object>('nodes')!;
      expect(nodesMap.keys, contains('p1'));

      final nodeMap = nodesMap.get('p1') as YMap;
      expect(nodeMap.get('id'), 'p1');
      expect(nodeMap.get('type'), 'paragraph');

      final ytext = doc.getText('content/p1')!;
      expect(ytext.toString(), 'Hello World');

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
          data: {'text': 'Hello World', 'spans': []},
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
          data: {'text': 'Hi', 'spans': []},
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
          data: {
            'text': 'Buy milk',
            'spans': [],
            'completed': true,
            'indent': 0,
          },
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ]);

      final updatedNode = mutableDoc.getNodeById('t1') as TaskNode;
      // Crucial: The node completion status must be successfully synced.
      expect(updatedNode.isComplete, isTrue);
    });

    test('completeTaskInYDoc with recurring task advances due date', () async {
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
        userId: 'test-user',
        coordinator: coordinator,
      );

      // Seed a recurring task in the YDoc.
      doc.transact((txn) {
        final nodeMap = YMap<Object>();
        nodeMap.set('id', 't1');
        nodeMap.set('position', 'a0');
        nodeMap.set('type', 'task');
        nodeMap.set('recurrence', 'daily');
        nodeMap.set('data', jsonEncode({
          'text': 'Daily task',
          'completed': false,
        }));
        doc.getMap<Object>('nodes')!.set('t1', nodeMap);
        doc.getText('content/t1')!.insert(0, 'Daily task');
      });

      final result = bridge.completeTaskInYDoc('t1', now: DateTime(2026, 7, 14));

      final nodesMap = doc.getMap<Object>('nodes')!;
      final t1Map = nodesMap.get('t1') as YMap;
      // Task should NOT be completed — it was reopened by recurrence
      expect(t1Map.get('completed'), isFalse);
      // Due date should have advanced
      expect(t1Map.get('dueDate'), '2026-07-15');
      // Composite keys should NOT be written
      expect(nodesMap.get('t1:completed'), isNull);
      expect(nodesMap.get('t1:dueDate'), isNull);

      bridge.dispose();
    });

    test('updateTaskMetadataInYDoc writes task metadata inside node YMap',
        () async {
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
        userId: 'test-user',
        coordinator: coordinator,
      );

      doc.transact((txn) {
        final nodeMap = YMap<Object>();
        nodeMap.set('id', 't1');
        nodeMap.set('position', 'a0');
        nodeMap.set('type', 'task');
        nodeMap.set('data', jsonEncode({'text': 'Task with dates'}));
        doc.getMap<Object>('nodes')!.set('t1', nodeMap);
        doc.getText('content/t1')!.insert(0, 'Task with dates');
      });

      bridge.updateTaskMetadataInYDoc(
        't1',
        dueDate: DateTime(2026, 8, 15),
        recurrence: 'weekly',
        reminder: '9am',
      );

      final nodesMap = doc.getMap<Object>('nodes')!;
      final t1Map = nodesMap.get('t1') as YMap;
      expect(t1Map.get('dueDate'), '2026-08-15');
      expect(t1Map.get('recurrence'), 'weekly');
      expect(t1Map.get('reminder'), '9am');
      // Composite keys should NOT be written
      expect(nodesMap.get('t1:dueDate'), isNull);
      expect(nodesMap.get('t1:recurrence'), isNull);
      expect(nodesMap.get('t1:reminder'), isNull);

      bridge.dispose();
    });

    test('updateTaskMetadataInYDoc with hasTime:true writes time in dueDate and hasTime flag',
        () async {
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
        userId: 'test-user',
        coordinator: coordinator,
      );

      doc.transact((txn) {
        final nodeMap = YMap<Object>();
        nodeMap.set('id', 't1');
        nodeMap.set('position', 'a0');
        nodeMap.set('type', 'task');
        nodeMap.set('data', jsonEncode({'text': 'Task with time'}));
        doc.getMap<Object>('nodes')!.set('t1', nodeMap);
        doc.getText('content/t1')!.insert(0, 'Task with time');
      });

      bridge.updateTaskMetadataInYDoc(
        't1',
        dueDate: DateTime(2026, 8, 15, 14, 30),
        recurrence: 'daily',
        hasTime: true,
      );

      final nodesMap = doc.getMap<Object>('nodes')!;
      final t1Map = nodesMap.get('t1') as YMap;
      expect(t1Map.get('dueDate'), '2026-08-15T14:30');
      expect(t1Map.get('recurrence'), 'daily');
      expect(t1Map.get('hasTime'), true);

      bridge.dispose();
    });

    test('updateTaskMetadataInYDoc with hasTime:false writes date-only dueDate',
        () async {
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
        userId: 'test-user',
        coordinator: coordinator,
      );

      doc.transact((txn) {
        final nodeMap = YMap<Object>();
        nodeMap.set('id', 't1');
        nodeMap.set('position', 'a0');
        nodeMap.set('type', 'task');
        nodeMap.set('data', jsonEncode({'text': 'Task all-day'}));
        doc.getMap<Object>('nodes')!.set('t1', nodeMap);
        doc.getText('content/t1')!.insert(0, 'Task all-day');
      });

      bridge.updateTaskMetadataInYDoc(
        't1',
        dueDate: DateTime(2026, 8, 15),
        hasTime: false,
      );

      final t1Map = doc.getMap<Object>('nodes')!.get('t1') as YMap;
      expect(t1Map.get('dueDate'), '2026-08-15');
      expect(t1Map.get('hasTime'), false);

      bridge.dispose();
    });

    test('updateTaskMetadataInYDoc simula persistencia da sheet (dueDate + hasTime + recurrence + clearReminder)',
        () async {
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
        userId: 'test-user',
        coordinator: coordinator,
      );

      doc.transact((txn) {
        final nodeMap = YMap<Object>();
        nodeMap.set('id', 't1');
        nodeMap.set('position', 'a0');
        nodeMap.set('type', 'task');
        nodeMap.set('data', jsonEncode({'text': 'Sheet metadata test'}));
        doc.getMap<Object>('nodes')!.set('t1', nodeMap);
        doc.getText('content/t1')!.insert(0, 'Sheet metadata test');
      });

      // Exatamente os parametros que showTaskMetadataSheet envia
      bridge.updateTaskMetadataInYDoc(
        't1',
        dueDate: DateTime(2026, 7, 18, 14, 30),
        clearDueDate: false,
        recurrence: 'daily',
        clearRecurrence: false,
        hasTime: true,
        reminder: null,
        clearReminder: true,
      );

      final t1Map = doc.getMap<Object>('nodes')!.get('t1') as YMap;
      expect(t1Map.get('dueDate'), '2026-07-18T14:30');
      expect(t1Map.get('hasTime'), true);
      expect(t1Map.get('recurrence'), 'daily');
      expect(t1Map.get('reminder'), isNull);

      bridge.dispose();
    });

    test('updateTaskMetadataInYDoc with clearRecurrence deletes recurrence',
        () async {
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
        userId: 'test-user',
        coordinator: coordinator,
      );

      doc.transact((txn) {
        final nodeMap = YMap<Object>();
        nodeMap.set('id', 't1');
        nodeMap.set('position', 'a0');
        nodeMap.set('type', 'task');
        nodeMap.set('recurrence', 'weekly');
        nodeMap.set('data', jsonEncode({'text': 'Task with recurrence'}));
        doc.getMap<Object>('nodes')!.set('t1', nodeMap);
        doc.getText('content/t1')!.insert(0, 'Task with recurrence');
      });

      bridge.updateTaskMetadataInYDoc(
        't1',
        clearRecurrence: true,
      );

      final t1Map = doc.getMap<Object>('nodes')!.get('t1') as YMap;
      expect(t1Map.get('recurrence'), isNull);

      bridge.dispose();
    });
  });
}

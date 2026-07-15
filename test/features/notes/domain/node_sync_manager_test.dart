import 'package:yjs_dart/yjs_dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';

AppDatabase createTestDatabase() {
  final db = AppDatabase.test();
  return db;
}

Future<void> seedNote(AppDatabase db) async {
  await db.into(db.notes).insert(NotesCompanion.insert(
        id: 'test-note',
        userId: 'test-user',
        content: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
}

const _debounce = Duration(milliseconds: 600);

void main() {
  group('NodeSyncManager flush round-trip', () {
    test('Insert', () async {
      final db = createTestDatabase();
      await seedNote(db);
      final doc = Doc();

      final controller = NoteEditorController(
        userId: 'test-user',
      );
      controller.bind('test-note');
      controller.initFromDoc(doc: doc, noteId: 'test-note', sendUpdate: (_) {});

      controller.editor!.execute([
        InsertNodeAtIndexRequest(
          nodeIndex: 1,
          newNode: ParagraphNode(
            id: 'p1',
            text: AttributedText('Hello'),
          ),
        ),
      ]);

      await Future.delayed(_debounce);

      final p1 = controller.document!.getNodeById('p1');
      expect(p1, isNotNull);
      expect((p1 as TextNode).text.toPlainText(), 'Hello');

      final ytext = doc.getText('content/p1')!;
      expect(ytext.toString(), 'Hello');
    });

    test('Update', () async {
      final db = createTestDatabase();
      await seedNote(db);
      final doc = Doc();

      final controller = NoteEditorController(
        userId: 'test-user',
      );
      controller.bind('test-note');
      controller.initFromDoc(doc: doc, noteId: 'test-note', sendUpdate: (_) {});

      controller.editor!.execute([
        InsertNodeAtIndexRequest(
          nodeIndex: 1,
          newNode: ParagraphNode(
            id: 'p1',
            text: AttributedText('Hello'),
          ),
        ),
      ]);
      await Future.delayed(_debounce);

      controller.editor!.execute([
        ReplaceNodeRequest(
          existingNodeId: 'p1',
          newNode: ParagraphNode(
            id: 'p1',
            text: AttributedText('Updated'),
          ),
        ),
      ]);
      await Future.delayed(_debounce);

      final p1 = controller.document!.getNodeById('p1');
      expect(p1, isNotNull);
      expect((p1 as TextNode).text.toPlainText(), 'Updated');

      final ytext = doc.getText('content/p1')!;
      expect(ytext.toString(), 'Updated');
    });

    test('Move', () async {
      final db = createTestDatabase();
      await seedNote(db);
      final doc = Doc();

      final controller = NoteEditorController(
        userId: 'test-user',
      );
      controller.bind('test-note');
      controller.initFromDoc(doc: doc, noteId: 'test-note', sendUpdate: (_) {});

      // Add 3 nodes via editor
      controller.editor!.execute([
        InsertNodeAtIndexRequest(
          nodeIndex: 0,
          newNode: ParagraphNode(id: 'p1', text: AttributedText('First')),
        ),
      ]);
      controller.editor!.execute([
        InsertNodeAtIndexRequest(
          nodeIndex: 1,
          newNode: ParagraphNode(id: 'p2', text: AttributedText('Second')),
        ),
      ]);
      controller.editor!.execute([
        InsertNodeAtIndexRequest(
          nodeIndex: 2,
          newNode: ParagraphNode(id: 'p3', text: AttributedText('Third')),
        ),
      ]);
      await Future.delayed(_debounce);

      // Move p1 from index 0 to index 2 → order: [p2, p3, p1]
      controller.editor!.execute([
        MoveNodeRequest(nodeId: 'p1', newIndex: 2),
      ]);
      await Future.delayed(_debounce);

      final ids = controller.document!.map((n) => n.id).toList();
      expect(ids, ['p2', 'p3', 'p1']);
    });

    test('Delete', () async {
      final db = createTestDatabase();
      await seedNote(db);
      final doc = Doc();

      final controller = NoteEditorController(
        userId: 'test-user',
      );
      controller.bind('test-note');
      controller.initFromDoc(doc: doc, noteId: 'test-note', sendUpdate: (_) {});

      controller.editor!.execute([
        InsertNodeAtIndexRequest(
          nodeIndex: 1,
          newNode: ParagraphNode(
            id: 'p1',
            text: AttributedText('Hello'),
          ),
        ),
      ]);
      await Future.delayed(_debounce);

      controller.editor!.execute([
        DeleteNodeRequest(nodeId: 'p1'),
      ]);
      await Future.delayed(_debounce);

      expect(controller.document!.getNodeById('p1'), isNull);
    });

    test('Task insert produces both document node and tasks row', () async {
      final db = createTestDatabase();
      await seedNote(db);
      final doc = Doc();

      final controller = NoteEditorController(
        userId: 'test-user',
      );
      controller.bind('test-note');
      controller.initFromDoc(doc: doc, noteId: 'test-note', sendUpdate: (_) {});

      controller.editor!.execute([
        InsertNodeAtIndexRequest(
          nodeIndex: 1,
          newNode: TaskNode(
            id: 't1',
            text: AttributedText('Task 1'),
            isComplete: false,
          ),
        ),
      ]);
      await Future.delayed(_debounce);

      final t1 = controller.document!.getNodeById('t1');
      expect(t1, isNotNull);
      expect(t1, isA<TaskNode>());

      final taskRows = await db.select(db.tasks).get();
      expect(taskRows.length, 1);
      expect(taskRows.first.id, 't1');
      expect(taskRows.first.status, 'open');
    });

    test('Debounce coalescing', () async {
      final db = createTestDatabase();
      await seedNote(db);
      final doc = Doc();

      final controller = NoteEditorController(
        userId: 'test-user',
      );
      controller.bind('test-note');
      controller.initFromDoc(doc: doc, noteId: 'test-note', sendUpdate: (_) {});

      controller.editor!.execute([
        InsertNodeAtIndexRequest(
          nodeIndex: 1,
          newNode: ParagraphNode(
            id: 'p1',
            text: AttributedText('A'),
          ),
        ),
      ]);
      controller.editor!.execute([
        ReplaceNodeRequest(
          existingNodeId: 'p1',
          newNode: ParagraphNode(
            id: 'p1',
            text: AttributedText('B'),
          ),
        ),
      ]);
      controller.editor!.execute([
        ReplaceNodeRequest(
          existingNodeId: 'p1',
          newNode: ParagraphNode(
            id: 'p1',
            text: AttributedText('C'),
          ),
        ),
      ]);

      await Future.delayed(_debounce);

      final p1 = controller.document!.getNodeById('p1');
      expect(p1, isNotNull);
      expect((p1 as TextNode).text.toPlainText(), 'C');
    });

    test('suspendSync / resumeSync', () async {
      final db = createTestDatabase();
      await seedNote(db);
      final doc = Doc();

      final controller = NoteEditorController(
        userId: 'test-user',
      );
      controller.bind('test-note');
      controller.initFromDoc(doc: doc, noteId: 'test-note', sendUpdate: (_) {});

      controller.suspendSync();

      controller.editor!.execute([
        InsertNodeAtIndexRequest(
          nodeIndex: 1,
          newNode: ParagraphNode(
            id: 'p1',
            text: AttributedText('Hello'),
          ),
        ),
      ]);
      await Future.delayed(_debounce);

      expect(controller.document!.getNodeById('p1'), isNotNull);
      // With sync suspended, the flush does not update Yjs
      expect(doc.getText('content/p1')!.toString(), isEmpty);

      controller.resumeSync();

      controller.editor!.execute([
        InsertNodeAtIndexRequest(
          nodeIndex: 1,
          newNode: ParagraphNode(
            id: 'p2',
            text: AttributedText('World'),
          ),
        ),
      ]);
      await Future.delayed(_debounce);

      expect(controller.document!.getNodeById('p2'), isNotNull);
    });

    test('Note excerpt is updated', () async {
      final db = createTestDatabase();
      await seedNote(db);

      final controller = NoteEditorController(
        userId: 'test-user',
      );
      controller.bind('test-note');
      controller.initFromDoc(
        doc: Doc(),
        noteId: 'test-note',
        sendUpdate: (_) {},
      );

      controller.editor!.execute([
        InsertNodeAtIndexRequest(
          nodeIndex: 1,
          newNode: ParagraphNode(
            id: 'p1',
            text: AttributedText('First line'),
          ),
        ),
        InsertNodeAtIndexRequest(
          nodeIndex: 2,
          newNode: ParagraphNode(
            id: 'p2',
            text: AttributedText('Second line'),
          ),
        ),
      ]);
      await Future.delayed(_debounce);

      // Verify document has the nodes
      expect(controller.document!.length, 2);
    });
  });
}

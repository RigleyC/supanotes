import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';

import '../_helpers/test_note_database.dart';

Future<void> seedNote(AppDatabase db,
    {String id = 'test-note', String userId = 'test-user'}) async {
  await db.into(db.notes).insert(NotesCompanion.insert(
        id: id,
        userId: userId,
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

      final controller = NoteEditorController(
        userId: 'test-user',
        database: db,
      );
      controller.bind('test-note');
      controller.initFromNodes(nodes: [], noteId: 'test-note');

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

      final rows = await db.select(db.noteNodes).get();
      expect(rows.length, 1);
      expect(rows.first.type, 'paragraph');
      final data = jsonDecode(rows.first.data) as Map<String, dynamic>;
      expect(data['text'], 'Hello');
    });

    test('Update', () async {
      final db = createTestDatabase();
      await seedNote(db);

      final controller = NoteEditorController(
        userId: 'test-user',
        database: db,
      );
      controller.bind('test-note');
      controller.initFromNodes(nodes: [], noteId: 'test-note');

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

      final rows = await db.select(db.noteNodes).get();
      expect(rows.length, 1);
      final data = jsonDecode(rows.first.data) as Map<String, dynamic>;
      expect(data['text'], 'Updated');
      expect(rows.first.isDirty, isTrue);
    });

    test('Move', () async {
      final db = createTestDatabase();
      await seedNote(db);

      // Seed 3 nodes at distinct positions directly in the DB
      final now = DateTime.now().toUtc();
      for (final entry in [
        ('p1', '1.0', 'First'),
        ('p2', '2.0', 'Second'),
        ('p3', '3.0', 'Third'),
      ]) {
        await db.into(db.noteNodes).insert(NoteNodesCompanion.insert(
          id: entry.$1,
          noteId: 'test-note',
          position: Value(entry.$2),
          type: 'paragraph',
          data: '{"text":"${entry.$3}"}',
          createdAt: now,
          updatedAt: now,
          isDirty: const Value(false),
          deletedAt: const Value(null),
        ));
      }

      // Load nodes from DB into the controller
      final storedNodes = await db.select(db.noteNodes).get();
      final controller = NoteEditorController(
        userId: 'test-user',
        database: db,
      );
      controller.bind('test-note');
      controller.initFromNodes(nodes: storedNodes, noteId: 'test-note');

      // Document: [p1, p2, p3]
      // Move p1 from index 0 to index 2 → order: [p2, p3, p1]
      controller.editor!.execute([
        MoveNodeRequest(nodeId: 'p1', newIndex: 2),
      ]);
      await Future.delayed(_debounce);

      final rows = await (db.select(db.noteNodes)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.position, mode: OrderingMode.asc)
            ]))
          .get();
      expect(rows.length, 3);
      expect(rows[0].id, 'p2');
      expect(rows[1].id, 'p3');
      expect(rows[2].id, 'p1');
    });

    test('Delete', () async {
      final db = createTestDatabase();
      await seedNote(db);

      final controller = NoteEditorController(
        userId: 'test-user',
        database: db,
      );
      controller.bind('test-note');
      controller.initFromNodes(nodes: [], noteId: 'test-note');

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

      final rows = await db.select(db.noteNodes).get();
      expect(rows.length, 1);
      expect(rows.first.deletedAt, isNotNull);
      expect(rows.first.isDirty, isTrue);
    });

    test('Task insert produces both noteNodes and tasks rows', () async {
      final db = createTestDatabase();
      await seedNote(db);

      final controller = NoteEditorController(
        userId: 'test-user',
        database: db,
      );
      controller.bind('test-note');
      controller.initFromNodes(nodes: [], noteId: 'test-note');

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

      final nodeRows = await db.select(db.noteNodes).get();
      expect(nodeRows.length, 1);
      expect(nodeRows.first.id, 't1');
      expect(nodeRows.first.type, 'task');

      final taskRows = await db.select(db.tasks).get();
      expect(taskRows.length, 1);
      expect(taskRows.first.id, 't1');
      expect(taskRows.first.status, 'open');
    });

    test('Debounce coalescing', () async {
      final db = createTestDatabase();
      await seedNote(db);

      final controller = NoteEditorController(
        userId: 'test-user',
        database: db,
      );
      controller.bind('test-note');
      controller.initFromNodes(nodes: [], noteId: 'test-note');

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

      final rows = await db.select(db.noteNodes).get();
      expect(rows.length, 1);
      final data = jsonDecode(rows.first.data) as Map<String, dynamic>;
      expect(data['text'], 'C');
    });

    test('suspendSync / resumeSync', () async {
      final db = createTestDatabase();
      await seedNote(db);

      final controller = NoteEditorController(
        userId: 'test-user',
        database: db,
      );
      controller.bind('test-note');
      controller.initFromNodes(nodes: [], noteId: 'test-note');

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

      var rows = await db.select(db.noteNodes).get();
      expect(rows, isEmpty);

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

      rows = await db.select(db.noteNodes).get();
      expect(rows.length, 1);
      expect(rows.first.id, 'p2');
    });

    test('Note excerpt is updated', () async {
      final db = createTestDatabase();
      await seedNote(db);

      final controller = NoteEditorController(
        userId: 'test-user',
        database: db,
      );
      controller.bind('test-note');
      controller.initFromNodes(nodes: [], noteId: 'test-note');

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

      final note = await (db.select(db.notes)
            ..where((t) => t.id.equals('test-note')))
          .getSingle();
      expect(note.content, isNotEmpty);
      expect(note.excerpt, isNotNull);
      expect(note.excerpt, isNotEmpty);
    });
  });
}

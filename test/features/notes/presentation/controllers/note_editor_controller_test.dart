import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';

import '../../_helpers/test_note_database.dart';

AppDatabase _createDb() => createTestDatabase();

NoteNode _paragraphNode({
  required String id,
  required String text,
  double position = 1.0,
}) {
  return NoteNode(
    id: id,
    noteId: 'test-note',
    position: position,
    type: 'paragraph',
    data: jsonEncode({'text': text, 'spans': []}),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    isDirty: false,
  );
}

NoteNode _imageNode({
  required String id,
  required String url,
  double position = 1.0,
}) {
  return NoteNode(
    id: id,
    noteId: 'test-note',
    position: position,
    type: 'image',
    data: jsonEncode({'url': url, 'alt': ''}),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    isDirty: false,
  );
}

void main() {
  group('updateNodesIncrementally', () {
    test('Add a node not yet in doc', () async {
      final db = _createDb();
      final controller = NoteEditorController(
        userId: 'test-user',
        database: db,
      );
      controller.bind('test-note');
      controller.initFromNodes(nodes: [], noteId: 'test-note');

      controller.updateNodesIncrementally([
        _paragraphNode(id: 'p1', text: 'Hello'),
      ]);

      final node = controller.document!.getNodeById('p1');
      expect(node, isNotNull);
      expect((node as TextNode).text.toPlainText(), 'Hello');
    });

    test('Remove a node missing from incoming', () async {
      final db = _createDb();
      final controller = NoteEditorController(
        userId: 'test-user',
        database: db,
      );
      controller.bind('test-note');
      controller.initFromNodes(
        nodes: [_paragraphNode(id: 'p1', text: 'Hello')],
        noteId: 'test-note',
      );

      controller.updateNodesIncrementally([]);

      expect(controller.document!.getNodeById('p1'), isNull);
    });

    test('Replace text on existing paragraph', () async {
      final db = _createDb();
      final controller = NoteEditorController(
        userId: 'test-user',
        database: db,
      );
      controller.bind('test-note');
      controller.initFromNodes(
        nodes: [_paragraphNode(id: 'p1', text: 'A')],
        noteId: 'test-note',
      );

      controller.updateNodesIncrementally([
        _paragraphNode(id: 'p1', text: 'B'),
      ]);

      final node = controller.document!.getNodeById('p1') as TextNode;
      expect(node.text.toPlainText(), 'B');
    });

    test(
        'Locally-dirty paragraph is protected from overwrite',
        () async {
      final db = _createDb();
      final controller = NoteEditorController(
        userId: 'test-user',
        database: db,
      );
      controller.bind('test-note');
      controller.initFromNodes(
        nodes: [_paragraphNode(id: 'p1', text: 'A')],
        noteId: 'test-note',
      );

      controller.editor!.execute([
        ReplaceNodeRequest(
          existingNodeId: 'p1',
          newNode: ParagraphNode(
            id: 'p1',
            text: AttributedText('A2'),
          ),
        ),
      ]);

      controller.updateNodesIncrementally([
        _paragraphNode(id: 'p1', text: 'B'),
      ]);

      final node = controller.document!.getNodeById('p1') as TextNode;
      expect(node.text.toPlainText(), 'A2');
    });

    test(
        'plan 047: locally-dirty paragraph is preserved on stale stream emission',
        () async {
      final db = _createDb();
      final controller = NoteEditorController(
        userId: 'test-user',
        database: db,
      );
      controller.bind('test-note');
      controller.initFromNodes(nodes: [], noteId: 'test-note');

      controller.editor!.execute([
        InsertNodeAtIndexRequest(
          nodeIndex: 0,
          newNode: ParagraphNode(
            id: 'p1',
            text: AttributedText('Hello'),
          ),
        ),
      ]);

      controller.updateNodesIncrementally([]);

      expect(controller.document!.getNodeById('p1'), isA<ParagraphNode>(),
          reason:
              'Plan 047: locally-dirty paragraph is preserved against stale stream');
    });

    test(
        '048: dispose flushes pending ops via flushNow',
        () async {
      final db = _createDb();
      await db.into(db.notes).insert(NotesCompanion.insert(
            id: 'test-note',
            userId: 'test-user',
            content: '',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ));

      final controller = NoteEditorController(
        userId: 'test-user',
        database: db,
      );
      controller.bind('test-note');
      controller.initFromNodes(nodes: [], noteId: 'test-note');

      controller.editor!.execute([
        InsertNodeAtIndexRequest(
          nodeIndex: 0,
          newNode: ParagraphNode(
            id: 'p1',
            text: AttributedText('Hello'),
          ),
        ),
      ]);

      await controller.dispose();

      final rows = await db.select(db.noteNodes).get();
      expect(rows.any((r) => r.id == 'p1'), isTrue,
          reason: '048: dispose calls flushNow which syncs ops before disposal');

      final note = await (db.select(db.notes)
            ..where((t) => t.id.equals('test-note')))
          .getSingle();
      expect(note.content, contains('Hello'));
    });

    test(
        'plan 049: remote image updates are applied correctly via serialization fallback',
        () async {
      final db = _createDb();
      final controller = NoteEditorController(
        userId: 'test-user',
        database: db,
      );
      controller.bind('test-note');
      controller.initFromNodes(
        nodes: [_imageNode(id: 'i1', url: 'oldurl')],
        noteId: 'test-note',
      );

      controller.updateNodesIncrementally([
        _imageNode(id: 'i1', url: 'newurl'),
      ]);

      final docNode = controller.document!.getNodeById('i1');
      expect(docNode, isNotNull);
      expect(docNode, isA<ImageNode>());
      expect((docNode as ImageNode).imageUrl, 'newurl');
    });

    test('plan 049: dirty image node preserves local changes', () async {
      final db = _createDb();
      final controller = NoteEditorController(
        userId: 'test-user',
        database: db,
      );
      controller.bind('test-note');
      controller.initFromNodes(
        nodes: [_imageNode(id: 'i1', url: 'oldurl')],
        noteId: 'test-note',
      );

      controller.editor!.execute([
        ReplaceNodeRequest(
          existingNodeId: 'i1',
          newNode: ImageNode(
            id: 'i1',
            imageUrl: 'localurl',
          ),
        ),
      ]);

      controller.updateNodesIncrementally([
        _imageNode(id: 'i1', url: 'newurl'),
      ]);

      final docNode = controller.document!.getNodeById('i1');
      expect(docNode, isNotNull);
      expect(docNode, isA<ImageNode>());
      expect((docNode as ImageNode).imageUrl, 'localurl');
    });
  });
}

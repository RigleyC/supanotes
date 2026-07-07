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
  group('NoteEditorController nodes lifecycle', () {
    test(
        'flushBeforePop deletes empty regular note through lifecycle callback',
        () async {
      String? deletedNoteId;
      final controller = NoteEditorController(
        userId: 'test-user',
        emptyNoteExit: (noteId) async {
          deletedNoteId = noteId;
        },
      );

      controller.initFromNodes(nodes: [], noteId: 'empty-note');

      controller.dispose();
      expect(deletedNoteId, 'empty-note');
    });
  });

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
        'BUG 048: dispose starts _drainQueue but does not await it',
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

      controller.dispose();
      await Future.delayed(const Duration(milliseconds: 50));

      final rows = await db.select(db.noteNodes).get();
      expect(rows.any((r) => r.id == 'p1'), isTrue,
          reason:
              'BUG 048: dispose starts _drainQueue async but does not await it; '
              'the flush happens to complete in time for in-memory DB');
    });

    test(
        'BUG 049: createNodeFromSchema does not handle image type, converting ImageNode to ParagraphNode',
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

      final docNode = controller.document!.getNodeById('i1')!;
      expect(docNode is ParagraphNode, isTrue,
          reason:
              'BUG 049: createNodeFromSchema returns ParagraphNode for image type, '
              'converting ImageNode to ParagraphNode on remote update');
    });
  });
}

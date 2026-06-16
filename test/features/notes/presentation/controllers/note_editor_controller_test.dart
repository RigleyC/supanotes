import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/domain/task_entry.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';

void main() {
  group('NoteEditorController snapshot save', () {
    test('document changes schedule one snapshot save with extracted title', () async {
      final savedCalls = <(String, String, String, List<TaskEntry>)>[];
      final controller = NoteEditorController(
        snapshotSave: (noteId, title, markdown, tasks) async {
          savedCalls.add((noteId, title, markdown, tasks));
        },
      );

      controller.init(content: 'hello');
      controller.bind('test-note');
      expect(savedCalls, isEmpty);

      controller.composer!.setSelectionWithReason(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: controller.document!.first.id,
            nodePosition: const TextNodePosition(offset: 0),
          ),
        ),
      );
      controller.editor!.execute([
        const InsertPlainTextAtCaretRequest('new title'),
      ]);

      await Future.delayed(const Duration(milliseconds: 600));
      expect(savedCalls.length, 1);
      expect(savedCalls.first.$2, 'new titlehello');
    });

    test('flushBeforePop deletes empty regular note through lifecycle callback', () async {
      String? deletedNoteId;
      final controller = NoteEditorController(
        snapshotSave: (noteId, title, markdown, tasks) async {},
        emptyNoteExit: (noteId) async {
          deletedNoteId = noteId;
        },
      );

      controller.init(content: '');
      controller.bind('empty-note');

      controller.dispose();
      expect(deletedNoteId, 'empty-note');
    });
  });

  group('H1 coercion', () {
    test('first node is coerced to header1 on init with plain text', () {
      final controller = NoteEditorController(
        snapshotSave: (noteId, title, markdown, tasks) async {},
      );

      controller.init(content: 'hello');
      controller.bind('test-note');

      final firstNode = controller.document!.first;
      expect(firstNode, isA<ParagraphNode>());
      expect(
        (firstNode as ParagraphNode).getMetadataValue('blockType'),
        header1Attribution,
      );
    });

    test('first node is coerced to header1 on init from markdown', () {
      final controller = NoteEditorController(
        snapshotSave: (noteId, title, markdown, tasks) async {},
      );

      controller.init(content: '## hello\n\nworld');
      controller.bind('test-note');

      final firstNode = controller.document!.first;
      expect(firstNode, isA<ParagraphNode>());
      expect(
        (firstNode as ParagraphNode).getMetadataValue('blockType'),
        header1Attribution,
      );
    });

    test('user changes first node block type — it is coerced back to H1', () {
      final controller = NoteEditorController(
        snapshotSave: (_, _, _, _) async {},
      );
      controller.init(content: 'hello');
      controller.bind('test');

      // Simulate user attempting to convert the first paragraph to a list item.
      controller.editor!.execute([
        ConvertParagraphToListItemRequest(
          nodeId: controller.document!.first.id,
          type: ListItemType.unordered,
        ),
      ]);

      final firstNode = controller.document!.first;
      expect(firstNode, isA<ParagraphNode>());
      expect(
        (firstNode as ParagraphNode).getMetadataValue('blockType'),
        header1Attribution,
      );
    });
  });
}

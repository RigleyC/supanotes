import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';

void main() {
  group('NoteEditorController snapshot save', () {
    test('document changes schedule one snapshot save', () async {
      final savedCalls = <(String, String)>[];
      final controller = NoteEditorController(
        snapshotSave: (noteId, content) async {
          savedCalls.add((noteId, content));
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
        snapshotSave: (noteId, content) async {},
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
}

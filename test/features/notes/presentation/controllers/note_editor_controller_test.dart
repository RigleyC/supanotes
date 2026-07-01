import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';

void main() {
  group('NoteEditorController nodes lifecycle', () {
    test('flushBeforePop deletes empty regular note through lifecycle callback', () async {
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
}

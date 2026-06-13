import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/domain/task_entry.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';

void main() {
  group('NoteEditorController snapshot save', () {
    test('title and document changes schedule one snapshot save', () async {
      final savedCalls = <(String, String, String, List<TaskEntry>)>[];
      final controller = NoteEditorController(
        editableTitle: true,
        snapshotSave: (noteId, title, markdown, tasks) async {
          savedCalls.add((noteId, title, markdown, tasks));
        },
      );

      controller.init(content: 'hello', title: 'world');
      controller.bind('test-note');
      expect(savedCalls, isEmpty);

      controller.titleController?.text = 'new title';
      controller.titleController?.notifyListeners();

      controller.document?.insertNodeAt(0, ParagraphNode(
        id: Editor.createNodeId(),
        text: AttributedText(' more'),
      ));

      await Future.delayed(const Duration(milliseconds: 600));
      expect(savedCalls.length, 1);
    });

    test('flushBeforePop deletes empty regular note through lifecycle callback', () async {
      String? deletedNoteId;
      final controller = NoteEditorController(
        editableTitle: true,
        snapshotSave: (noteId, title, markdown, tasks) async {},
        emptyNoteExit: (noteId) async {
          deletedNoteId = noteId;
        },
      );

      controller.init(content: '', title: '');
      controller.bind('empty-note');

      controller.dispose();
      expect(deletedNoteId, 'empty-note');
    });
  });
}

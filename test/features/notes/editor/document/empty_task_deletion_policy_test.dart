import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_controller.dart';
import 'package:super_editor/super_editor.dart';

void main() {
  test(
    'backspace at beginning of an empty task removes it before a following list item',
    () async {
      final controller = NoteEditorController(
        userId: 'user-1',
        noteId: 'note-1',
        nodes: [
          TaskNode(
            id: 'task-1',
            text: AttributedText(),
            isComplete: false,
          ),
          ListItemNode.unordered(
            id: 'list-1',
            text: AttributedText('List item'),
          ),
        ],
      );
      addTearDown(controller.dispose);

      final task = controller.document.getNodeById('task-1')!;
      controller.composer.setSelectionWithReason(
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: 'task-1',
            nodePosition: TextNodePosition(offset: 0),
          ),
        ),
      );

      controller.editor.execute([
        DeleteUpstreamAtBeginningOfNodeRequest(task),
      ]);

      expect(controller.document.getNodeById('task-1'), isNull);
      expect(controller.document.nodeCount, 1);
      expect(controller.document.first.id, 'list-1');
      expect(
        controller.composer.selection,
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: 'list-1',
            nodePosition: TextNodePosition(offset: 0),
          ),
        ),
      );
    },
  );
}

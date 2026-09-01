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

      _backspaceAtBeginningOfTask(controller, 'task-1');

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

  test(
    'backspace on an empty task after text removes it and moves caret upstream',
    () async {
      final controller = NoteEditorController(
        userId: 'user-1',
        noteId: 'note-1',
        nodes: [
          ParagraphNode(id: 'paragraph-1', text: AttributedText('Before')),
          TaskNode(
            id: 'task-1',
            text: AttributedText(),
            isComplete: false,
          ),
        ],
      );
      addTearDown(controller.dispose);

      _backspaceAtBeginningOfTask(controller, 'task-1');

      expect(controller.document.getNodeById('task-1'), isNull);
      expect(
        controller.composer.selection,
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: 'paragraph-1',
            nodePosition: TextNodePosition(offset: 6),
          ),
        ),
      );
    },
  );

  test('a single empty task still converts to an editable paragraph', () async {
    final controller = NoteEditorController(
      userId: 'user-1',
      noteId: 'note-1',
      nodes: [
        TaskNode(
          id: 'task-1',
          text: AttributedText(),
          isComplete: false,
        ),
      ],
    );
    addTearDown(controller.dispose);

    _backspaceAtBeginningOfTask(controller, 'task-1');

    expect(controller.document.nodeCount, 1);
    expect(controller.document.getNodeById('task-1'), isA<ParagraphNode>());
  });

  test('a non-empty task keeps the default task-to-paragraph behavior', () async {
    final controller = NoteEditorController(
      userId: 'user-1',
      noteId: 'note-1',
      nodes: [
        TaskNode(
          id: 'task-1',
          text: AttributedText('Keep me'),
          isComplete: false,
        ),
        ParagraphNode(id: 'paragraph-1', text: AttributedText('After')),
      ],
    );
    addTearDown(controller.dispose);

    _backspaceAtBeginningOfTask(controller, 'task-1');

    final node = controller.document.getNodeById('task-1');
    expect(node, isA<ParagraphNode>());
    expect((node! as ParagraphNode).text.toPlainText(), 'Keep me');
    expect(controller.document.nodeCount, 2);
  });
}

void _backspaceAtBeginningOfTask(
  NoteEditorController controller,
  String taskId,
) {
  final task = controller.document.getNodeById(taskId)!;
  controller.composer.setSelectionWithReason(
    DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: taskId,
        nodePosition: const TextNodePosition(offset: 0),
      ),
    ),
  );

  controller.editor.execute([
    DeleteUpstreamAtBeginningOfNodeRequest(task),
  ]);
}

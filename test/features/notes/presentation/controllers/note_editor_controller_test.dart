import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';

void main() {
  test('default document starts with the canonical init paragraph', () async {
    final controller = NoteEditorController(userId: 'user-1', noteId: 'note-1');

    expect(controller.document.nodeCount, 1);
    expect(controller.document.first, isA<ParagraphNode>());
    expect(controller.document.first.id, 'init');
    await controller.dispose();
  });

  test(
    'an explicitly empty node list also receives the init paragraph',
    () async {
      final controller = NoteEditorController(
        userId: 'user-1',
        noteId: 'note-1',
        nodes: const [],
      );

      expect(controller.document.nodeCount, 1);
      expect(controller.document.first.id, 'init');
      await controller.dispose();
    },
  );

  test('task metadata mutations preserve the task indentation', () async {
    final controller = NoteEditorController(
      userId: 'user-1',
      noteId: 'note-1',
      nodes: [
        TaskNode(
          id: 'task-parent',
          text: AttributedText('Parent task'),
          isComplete: false,
          indent: 0,
        ),
        TaskNode(
          id: 'task-1',
          text: AttributedText('Nested task'),
          isComplete: false,
          indent: 1,
          metadata: {'dueDate': '2026-07-31T10:00:00.000Z'},
        ),
      ],
    );

    expect((controller.document.getNodeById('task-1') as TaskNode).indent, 1);
    controller.updateTaskMetadataInEditor('task-1', reminder: '10m');
    expect((controller.document.getNodeById('task-1') as TaskNode).indent, 1);

    controller.completeTaskInEditor(
      'task-1',
      now: DateTime.utc(2026, 7, 31, 12),
    );
    expect((controller.document.getNodeById('task-1') as TaskNode).indent, 1);

    controller.reopenTaskInEditor('task-1');
    expect((controller.document.getNodeById('task-1') as TaskNode).indent, 1);
    await controller.dispose();
  });

  test(
    'completes the current occurrence when the stored date is stale',
    () async {
      final controller = NoteEditorController(
        userId: 'user-1',
        noteId: 'note-1',
        nodes: [
          TaskNode(
            id: 'task-1',
            text: AttributedText('Daily task'),
            isComplete: false,
            metadata: {
              'dueDate': '2026-07-01T09:00:00.000',
              'hasTime': true,
              'recurrenceRule': 'daily',
            },
          ),
        ],
      );

      final result = controller.completeTaskInEditor(
        'task-1',
        now: DateTime(2026, 7, 4, 12),
      );

      final expectedScheduledAt = DateTime(2026, 7, 4, 9);
      final expectedNextDue = DateTime(2026, 7, 5, 9);
      expect(result?.scheduledAt, expectedScheduledAt);
      expect(result?.nextDue, expectedNextDue);
      final task = controller.document.getNodeById('task-1')! as TaskNode;
      expect(task.metadata['dueDate'], expectedNextDue.toIso8601String());
      expect(
        (task.metadata['completions'] as Map).keys,
        contains(expectedScheduledAt.toUtc().toIso8601String()),
      );
      await controller.dispose();
    },
  );

  test('stale upload failure does not mutate an inactive editor', () async {
    final upload = Completer<void>();
    var active = true;
    var errorCalls = 0;
    final controller = NoteEditorController(
      userId: 'user-1',
      noteId: 'note-1',
      nodes: [ParagraphNode(id: 'paragraph-1', text: AttributedText())],
    );
    const position = DocumentPosition(
      nodeId: 'paragraph-1',
      nodePosition: TextNodePosition(offset: 0),
    );
    controller.composer.setSelectionWithReason(
      const DocumentSelection(base: position, extent: position),
    );
    controller.attachMutationGuard(() {
      if (!active) throw StateError('inactive session');
    });

    controller.attachFileFromPath(
      filePath: 'attachment.txt',
      mimeType: 'text/plain',
      onUploadFile: (_, _, _, _) => upload.future,
      onError: () => errorCalls++,
    );
    expect(controller.document.nodeCount, 2);

    active = false;
    upload.completeError(StateError('upload failed'));
    await pumpEventQueue();

    expect(controller.document.nodeCount, 2);
    expect(errorCalls, 0);
    await controller.dispose();
  });

  test('hidden tasks cannot be crossed by downstream deletion', () async {
    final controller = NoteEditorController(
      userId: 'user-1',
      noteId: 'note-1',
      nodes: [
        ParagraphNode(id: 'paragraph-1', text: AttributedText('visible')),
        TaskNode(
          id: 'task-hidden',
          text: AttributedText('completed'),
          isComplete: true,
        ),
      ],
    );
    addTearDown(controller.dispose);

    controller.setHiddenTaskPredicate((node) => node.id == 'task-hidden');
    controller.composer.setSelectionWithReason(
      const DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: 'paragraph-1',
          nodePosition: TextNodePosition(offset: 7),
        ),
      ),
    );

    controller.editor.execute([const DeleteDownstreamRequest()]);

    expect(controller.document.nodeCount, 2);
    expect(
      (controller.document.getNodeById('paragraph-1')! as ParagraphNode).text
          .toPlainText(),
      'visible',
    );
    expect(
      (controller.document.getNodeById('task-hidden')! as TaskNode).text
          .toPlainText(),
      'completed',
    );
  });

  test('hidden tasks reject direct text insertion', () async {
    final controller = NoteEditorController(
      userId: 'user-1',
      noteId: 'note-1',
      nodes: [
        TaskNode(
          id: 'task-hidden',
          text: AttributedText('completed'),
          isComplete: true,
        ),
      ],
    );
    addTearDown(controller.dispose);

    controller.setHiddenTaskPredicate((node) => node.id == 'task-hidden');
    controller.editor.execute([
      InsertTextRequest(
        documentPosition: const DocumentPosition(
          nodeId: 'task-hidden',
          nodePosition: TextNodePosition(offset: 9),
        ),
        textToInsert: '!',
        attributions: const {},
      ),
    ]);

    expect(
      (controller.document.getNodeById('task-hidden')! as TaskNode).text
          .toPlainText(),
      'completed',
    );
  });
}

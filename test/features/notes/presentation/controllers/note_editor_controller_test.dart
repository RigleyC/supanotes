import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_controller.dart';
import 'package:supanotes/features/tasks/domain/task_schedule_identity.dart';
import 'package:super_editor/super_editor.dart';

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
        ),
        TaskNode(
          id: 'task-1',
          text: AttributedText('Nested task'),
          isComplete: false,
          indent: 1,
          metadata: const {'dueDate': '2026-07-31T10:00:00.000Z'},
        ),
      ],
    );

    expect((controller.document.getNodeById('task-1')! as TaskNode).indent, 1);
    controller.updateTaskMetadataInEditor('task-1', reminder: '10m');
    expect((controller.document.getNodeById('task-1')! as TaskNode).indent, 1);

    controller.completeTaskInEditor(
      'task-1',
      now: DateTime.utc(2026, 7, 31, 12),
    );
    expect((controller.document.getNodeById('task-1')! as TaskNode).indent, 1);

    controller.reopenTaskInEditor('task-1');
    expect((controller.document.getNodeById('task-1')! as TaskNode).indent, 1);
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
            metadata: const {
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
      expect(task.metadata['dueDate'], '2026-07-01T09:00:00.000');
      expect(
        (task.metadata['completions'] as Map).keys,
        contains(scheduledAtKey(expectedScheduledAt, hasTime: true)),
      );
      await controller.dispose();
    },
  );

  test(
    'early recurring completion keeps the anchor and advances by history',
    () async {
      final controller = NoteEditorController(
        userId: 'user-1',
        noteId: 'note-1',
        nodes: [
          TaskNode(
            id: 'task-1',
            text: AttributedText('Weekly task'),
            isComplete: false,
            metadata: const {
              'dueDate': '2026-08-12T09:00:00.000',
              'hasTime': true,
              'recurrenceRule': 'weekly',
            },
          ),
        ],
      );

      final result = controller.completeTaskInEditor(
        'task-1',
        now: DateTime(2026, 8, 10, 14),
      );

      expect(result?.scheduledAt, DateTime(2026, 8, 12, 9));
      expect(result?.nextDue, DateTime(2026, 8, 19, 9));
      final task = controller.document.getNodeById('task-1')! as TaskNode;
      expect(task.metadata['dueDate'], '2026-08-12T09:00:00.000');
      expect(
        (task.metadata['completions'] as Map).values,
        contains(DateTime(2026, 8, 10, 14).toUtc().toIso8601String()),
      );
      await controller.dispose();
    },
  );

  test('stores a non-recurring completion instant in UTC', () async {
    final controller = NoteEditorController(
      userId: 'user-1',
      noteId: 'note-1',
      nodes: [
        TaskNode(
          id: 'task-1',
          text: AttributedText('One-time task'),
          isComplete: false,
          metadata: const {
            'dueDate': '2026-08-12T09:00:00.000',
            'hasTime': true,
          },
        ),
      ],
    );

    final now = DateTime(2026, 8, 10, 14);
    controller.completeTaskInEditor('task-1', now: now);

    final task = controller.document.getNodeById('task-1')! as TaskNode;
    expect(task.isComplete, true);
    expect(task.metadata['dueDate'], isNull);
    expect(task.metadata['lastCompletedAt'], now.toUtc().toIso8601String());
    await controller.dispose();
  });

  test(
    'allows consecutive early completions without moving the anchor',
    () async {
      final controller = NoteEditorController(
        userId: 'user-1',
        noteId: 'note-1',
        nodes: [
          TaskNode(
            id: 'task-1',
            text: AttributedText('Weekly task'),
            isComplete: false,
            metadata: const {
              'dueDate': '2026-08-12T09:00:00.000',
              'hasTime': true,
              'recurrenceRule': 'weekly',
            },
          ),
        ],
      );

      final first = controller.completeTaskInEditor(
        'task-1',
        now: DateTime(2026, 8, 10, 14),
      );
      final second = controller.completeTaskInEditor(
        'task-1',
        now: DateTime(2026, 8, 10, 15),
      );

      expect(first?.scheduledAt, DateTime(2026, 8, 12, 9));
      expect(second?.scheduledAt, DateTime(2026, 8, 19, 9));
      final task = controller.document.getNodeById('task-1')! as TaskNode;
      expect(task.metadata['dueDate'], '2026-08-12T09:00:00.000');
      expect(
        (task.metadata['completions'] as Map).keys,
        containsAll(['2026-08-12T09:00:00.000', '2026-08-19T09:00:00.000']),
      );
      await controller.dispose();
    },
  );

  test(
    'reopens an occurrence regardless of its old UTC key representation',
    () async {
      final controller = NoteEditorController(
        userId: 'user-1',
        noteId: 'note-1',
        nodes: [
          TaskNode(
            id: 'task-1',
            text: AttributedText('All-day task'),
            isComplete: false,
            metadata: const {
              'dueDate': '2026-08-12T00:00:00.000',
              'hasTime': false,
              'recurrenceRule': 'weekly',
              'completions': {
                '2026-08-12T03:00:00.000Z': '2026-08-10T14:00:00.000Z',
              },
            },
          ),
        ],
      );

      controller.reopenTaskInEditor(
        'task-1',
        scheduledAt: DateTime(2026, 8, 12),
      );

      final task = controller.document.getNodeById('task-1')! as TaskNode;
      expect(task.metadata['completions'], isEmpty);
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

  test('select all includes visible content across hidden tasks', () async {
    final controller = NoteEditorController(
      userId: 'user-1',
      noteId: 'note-1',
      nodes: [
        ParagraphNode(id: 'before', text: AttributedText('Before')),
        TaskNode(
          id: 'task-hidden',
          text: AttributedText('completed'),
          isComplete: true,
        ),
        ParagraphNode(id: 'after', text: AttributedText('After')),
      ],
    );
    addTearDown(controller.dispose);

    controller.setHiddenTaskPredicate((node) => node.id == 'task-hidden');

    expect(selectAll(controller.editor), isTrue);
    expect(
      controller.composer.selection,
      const DocumentSelection(
        base: DocumentPosition(
          nodeId: 'before',
          nodePosition: TextNodePosition(offset: 0),
        ),
        extent: DocumentPosition(
          nodeId: 'after',
          nodePosition: TextNodePosition(offset: 5),
        ),
      ),
    );
  });

  test(
    'deleting a selection across hidden tasks keeps the hidden task',
    () async {
      final controller = NoteEditorController(
        userId: 'user-1',
        noteId: 'note-1',
        nodes: [
          ParagraphNode(id: 'before', text: AttributedText('Before')),
          TaskNode(
            id: 'task-hidden',
            text: AttributedText('completed'),
            isComplete: true,
          ),
          ParagraphNode(id: 'after', text: AttributedText('After')),
        ],
      );
      addTearDown(controller.dispose);

      controller.setHiddenTaskPredicate((node) => node.id == 'task-hidden');
      expect(selectAll(controller.editor), isTrue);

      controller.editor.execute([
        const DeleteSelectionRequest(TextAffinity.downstream),
      ]);

      expect(controller.document.nodeCount, 2);
      expect(controller.document.getNodeById('task-hidden'), isA<TaskNode>());
      expect(controller.document.last, isA<ParagraphNode>());
      expect(
        (controller.document.last as ParagraphNode).text.toPlainText(),
        '',
      );
      expect(
        controller.composer.selection,
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: 'after',
            nodePosition: TextNodePosition(offset: 0),
          ),
        ),
      );
    },
  );

  test('hidden tasks do not block editing a list item below', () async {
    final controller = NoteEditorController(
      userId: 'user-1',
      noteId: 'note-1',
      nodes: [
        TaskNode(
          id: 'task-hidden',
          text: AttributedText('completed'),
          isComplete: true,
        ),
        ListItemNode.unordered(id: 'list-below', text: AttributedText('Item')),
      ],
    );
    addTearDown(controller.dispose);

    controller.setHiddenTaskPredicate((node) => node.id == 'task-hidden');
    controller.composer.setSelectionWithReason(
      const DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: 'list-below',
          nodePosition: TextNodePosition(offset: 0),
        ),
      ),
    );

    controller.editor.execute([const DeleteUpstreamRequest()]);

    expect(controller.document.getNodeById('task-hidden'), isA<TaskNode>());
    expect(controller.document.getNodeById('list-below'), isA<ParagraphNode>());
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

  test('hidden tasks reject direct node deletion', () async {
    final controller = NoteEditorController(
      userId: 'user-1',
      noteId: 'note-1',
      nodes: [
        TaskNode(
          id: 'task-hidden',
          text: AttributedText('completed'),
          isComplete: true,
        ),
        ParagraphNode(id: 'paragraph-below', text: AttributedText('Below')),
      ],
    );
    addTearDown(controller.dispose);

    controller.setHiddenTaskPredicate((node) => node.id == 'task-hidden');
    controller.editor.execute([
      DeleteNodeRequest(nodeId: 'task-hidden'),
    ]);

    expect(controller.document.getNodeById('task-hidden'), isA<TaskNode>());
    expect(controller.document.nodeCount, 2);
  });

  test('clears selection when the selected task becomes hidden', () async {
    final controller = NoteEditorController(
      userId: 'user-1',
      noteId: 'note-1',
      nodes: [
        TaskNode(
          id: 'task-1',
          text: AttributedText('Complete me'),
          isComplete: false,
        ),
      ],
    );
    addTearDown(controller.dispose);

    controller.setHiddenTaskPredicate((node) => node.isComplete);
    controller.composer.setSelectionWithReason(
      const DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: 'task-1',
          nodePosition: TextNodePosition(offset: 4),
        ),
      ),
    );

    controller.editor.execute([
      ReplaceNodeRequest(
        existingNodeId: 'task-1',
        newNode: TaskNode(
          id: 'task-1',
          text: AttributedText('Complete me'),
          isComplete: true,
        ),
      ),
    ]);

    expect(controller.composer.selection, isNull);
  });

  test('backspace skips a hidden task between visible paragraphs', () async {
    final controller = NoteEditorController(
      userId: 'user-1',
      noteId: 'note-1',
      nodes: [
        ParagraphNode(id: 'before', text: AttributedText('Before')),
        TaskNode(
          id: 'task-hidden',
          text: AttributedText('completed'),
          isComplete: true,
        ),
        ParagraphNode(id: 'after', text: AttributedText('After')),
      ],
    );
    addTearDown(controller.dispose);

    controller.setHiddenTaskPredicate((node) => node.id == 'task-hidden');
    controller.composer.setSelectionWithReason(
      const DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: 'after',
          nodePosition: TextNodePosition(offset: 0),
        ),
      ),
    );

    controller.editor.execute([const DeleteUpstreamRequest()]);

    expect(controller.document.nodeCount, 3);
    expect(
      controller.composer.selection,
      const DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: 'before',
          nodePosition: TextNodePosition(offset: 6),
        ),
      ),
    );
  });

  test('delete skips a hidden task between visible paragraphs', () async {
    final controller = NoteEditorController(
      userId: 'user-1',
      noteId: 'note-1',
      nodes: [
        ParagraphNode(id: 'before', text: AttributedText('Before')),
        TaskNode(
          id: 'task-hidden',
          text: AttributedText('completed'),
          isComplete: true,
        ),
        ParagraphNode(id: 'after', text: AttributedText('After')),
      ],
    );
    addTearDown(controller.dispose);

    controller.setHiddenTaskPredicate((node) => node.id == 'task-hidden');
    controller.composer.setSelectionWithReason(
      const DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: 'before',
          nodePosition: TextNodePosition(offset: 6),
        ),
      ),
    );

    controller.editor.execute([const DeleteDownstreamRequest()]);

    expect(controller.document.nodeCount, 3);
    expect(
      controller.composer.selection,
      const DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: 'after',
          nodePosition: TextNodePosition(offset: 0),
        ),
      ),
    );
  });
}

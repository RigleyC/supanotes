import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/editor/document/document_projection_applier.dart';
import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';
import 'package:supanotes/features/notes/editor/sync/note_operation_contract.dart';
import 'package:super_editor/super_editor.dart';

void main() {
  test('moves a block after a later block', () {
    final document = MutableDocument(
      nodes: [
        ParagraphNode(id: 'block-a', text: AttributedText('A')),
        ParagraphNode(id: 'block-b', text: AttributedText('B')),
        ParagraphNode(id: 'block-c', text: AttributedText('C')),
        ParagraphNode(id: 'block-d', text: AttributedText('D')),
      ],
    );
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: MutableDocumentComposer(),
    );
    final applier = DocumentProjectionApplier(
      document: document,
      editor: editor,
      codec: const NoteDocumentCodec(),
    );
    applier.applyOperationPayload(
      kind: NoteOperationWireNames.moveBlock,
      blockId: 'block-a',
      payload: const {'blockId': 'block-a', 'afterBlockId': 'block-c'},
    );

    expect(document.toList().map((node) => node.id), [
      'block-b',
      'block-c',
      'block-a',
      'block-d',
    ]);
  });

  test('preserves task indentation when applying a text delta', () {
    final document = MutableDocument(
      nodes: [
        TaskNode(
          id: 'task-1',
          text: AttributedText('Task'),
          isComplete: false,
          indent: 2,
        ),
      ],
    );
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: MutableDocumentComposer(),
    );
    final applier = DocumentProjectionApplier(
      document: document,
      editor: editor,
      codec: const NoteDocumentCodec(),
    );

    applier.applyOperationPayload(
      kind: NoteOperationWireNames.textDelta,
      blockId: 'task-1',
      payload: const {
        'ops': [
          {'retain': 4},
          {'insert': '!'},
        ],
      },
    );

    final task = document.getNodeById('task-1')! as TaskNode;
    expect(task.text.toPlainText(), 'Task!');
    expect(task.indent, 2);
  });

  test('applies and clears list indentation metadata', () {
    final document = MutableDocument(
      nodes: [
        ListItemNode.unordered(
          id: 'list-1',
          text: AttributedText('Nested list'),
        ),
      ],
    );
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: MutableDocumentComposer(),
    );
    final applier = DocumentProjectionApplier(
      document: document,
      editor: editor,
      codec: const NoteDocumentCodec(),
    );

    applier.applyOperationPayload(
      kind: NoteOperationWireNames.setBlockMetadata,
      blockId: 'list-1',
      payload: const {
        'metadata': {'indent': 2},
      },
    );
    expect((document.getNodeById('list-1')! as ListItemNode).indent, 2);

    applier.applyOperationPayload(
      kind: NoteOperationWireNames.setBlockMetadata,
      blockId: 'list-1',
      payload: const {
        'metadata': {'indent': null},
      },
    );
    expect((document.getNodeById('list-1')! as ListItemNode).indent, 0);
  });

  test('preserves task indentation when applying metadata', () {
    final document = MutableDocument(
      nodes: [
        TaskNode(
          id: 'task-1',
          text: AttributedText('Nested task'),
          isComplete: false,
          indent: 2,
        ),
      ],
    );
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: MutableDocumentComposer(),
    );
    final applier = DocumentProjectionApplier(
      document: document,
      editor: editor,
      codec: const NoteDocumentCodec(),
    );

    applier.applyOperationPayload(
      kind: NoteOperationWireNames.setBlockMetadata,
      blockId: 'task-1',
      payload: const {
        'metadata': {
          'completions': {'2026-08-12': '2026-08-12T10:00:00Z'},
        },
      },
    );

    final task = document.getNodeById('task-1')! as TaskNode;
    expect(task.metadata['completions'], isA<Map>());
    expect(task.indent, 2);
  });

  test('preserves task metadata when changing a block type to task', () {
    final document = MutableDocument(
      nodes: [
        ParagraphNode(
          id: 'task-1',
          text: AttributedText('Review task'),
          metadata: const {
            'dueDate': '2099-01-02T10:00:00.000Z',
            'hasTime': true,
            'recurrenceRule': 'weekly',
            'reminder': 'at_time',
          },
        ),
      ],
    );
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: MutableDocumentComposer(),
    );
    final applier = DocumentProjectionApplier(
      document: document,
      editor: editor,
      codec: const NoteDocumentCodec(),
    );

    applier.applyOperationPayload(
      kind: NoteOperationWireNames.setBlockType,
      blockId: 'task-1',
      payload: const {'type': 'task'},
    );

    final task = document.getNodeById('task-1')! as TaskNode;
    expect(task.metadata['dueDate'], '2099-01-02T10:00:00.000Z');
    expect(task.metadata['hasTime'], true);
    expect(task.metadata['recurrenceRule'], 'weekly');
    expect(task.metadata['reminder'], 'at_time');
  });

  test(
    'keeps capture suppressed when rebuilding a malformed snapshot fails',
    () async {
      final document = MutableDocument(
        nodes: [ParagraphNode(id: 'block-1', text: AttributedText('Initial'))],
      );
      final editor = createDefaultDocumentEditor(
        document: document,
        composer: MutableDocumentComposer(),
      );
      final applier = DocumentProjectionApplier(
        document: document,
        editor: editor,
        codec: const NoteDocumentCodec(),
      );
      var suppressCalls = 0;
      var resumeCalls = 0;
      var mirrorCalls = 0;

      await expectLater(
        applier.rebuildFromSnapshot(
          snapshot: const {
            'blocks': [42],
          },
          pendingOps: null,
          repairPersistedSnapshot: false,
          suppressCapture: () => suppressCalls++,
          resumeCapture: () => resumeCalls++,
          rebuildMirror: () => mirrorCalls++,
        ),
        throwsA(isA<TypeError>()),
      );

      expect(suppressCalls, 1);
      expect(resumeCalls, 0);
      expect(mirrorCalls, 0);
    },
  );

  test('rejects mutation operations in a strict remote snapshot', () async {
    final document = MutableDocument(
      nodes: [ParagraphNode(id: 'block-1', text: AttributedText('Initial'))],
    );
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: MutableDocumentComposer(),
    );
    final applier = DocumentProjectionApplier(
      document: document,
      editor: editor,
      codec: const NoteDocumentCodec(),
    );

    await expectLater(
      applier.rebuildFromSnapshot(
        snapshot: const {
          'blocks': [
            {
              'id': 'block-1',
              'type': 'paragraph',
              'delta': [
                {'insert': 'Remote'},
                {'delete': 6},
              ],
              'metadata': {},
            },
          ],
        },
        pendingOps: null,
        repairPersistedSnapshot: false,
        suppressCapture: () {},
        resumeCapture: () {},
        rebuildMirror: () {},
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'skips the rebuild and preserves composition when snapshot plus pending '
    'ops already match the current document',
    () async {
      final document = MutableDocument(
        nodes: [ParagraphNode(id: 'block-1', text: AttributedText('Hello sim'))],
      );
      final composer = MutableDocumentComposer();
      final editor = createDefaultDocumentEditor(
        document: document,
        composer: composer,
      );
      final applier = DocumentProjectionApplier(
        document: document,
        editor: editor,
        codec: const NoteDocumentCodec(),
      );
      var suppressCalls = 0;
      var resumeCalls = 0;
      var mirrorCalls = 0;

      const before = DocumentSelection(
        base: DocumentPosition(
          nodeId: 'block-1',
          nodePosition: TextNodePosition(offset: 8),
        ),
        extent: DocumentPosition(
          nodeId: 'block-1',
          nodePosition: TextNodePosition(offset: 10),
        ),
      );
      editor.execute([
        const ChangeSelectionRequest(
          before,
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction,
        ),
      ]);

      await applier.rebuildFromSnapshot(
        snapshot: const {
          'blocks': [
            {
              'id': 'block-1',
              'type': 'paragraph',
              'delta': [
                {'insert': 'Hello'},
              ],
            },
          ],
        },
        pendingOps: [
          PendingNoteOperationData(
            operationId: 'pending-1',
            noteId: 'note-1',
            baseRevision: 1,
            ordinal: 0,
            kind: NoteOperationWireNames.textDelta,
            blockId: 'block-1',
            payloadJson: '{"ops":[{"retain":5},{"insert":" sim"}]}',
            createdAt: DateTime.utc(2026, 8, 15),
            status: 'pending',
            attemptCount: 0,
          ),
        ],
        repairPersistedSnapshot: false,
        suppressCapture: () => suppressCalls++,
        resumeCapture: () => resumeCalls++,
        rebuildMirror: () => mirrorCalls++,
      );

      expect(suppressCalls, 1);
      expect(resumeCalls, 1);
      expect(mirrorCalls, 1);
      final node = document.getNodeById('block-1')! as TextNode;
      expect(node.text.toPlainText(), 'Hello sim');
      expect(composer.selection, isNotNull);
      expect(composer.selection!.base.nodeId, 'block-1');
      expect((composer.selection!.base.nodePosition as TextNodePosition).offset, 8);
      expect(
        (composer.selection!.extent.nodePosition as TextNodePosition).offset,
        10,
      );
    },
  );
}

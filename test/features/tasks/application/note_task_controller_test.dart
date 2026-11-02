import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_codec.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_controller.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_session.dart';
import 'package:supanotes/features/notes/editor/sync/note_session_handle.dart';
import 'package:supanotes/features/tasks/application/note_task_controller.dart';
import 'package:supanotes/features/tasks/domain/task_list_item.dart';
import 'package:supanotes/features/notes/editor/document/note_blocks.dart';

void main() {
  test(
    'completes a note task through its document session and flushes it',
    () async {
      final controller = NoteEditorController(
        userId: 'user-1',
        noteId: 'note-1',
        blocks: [
          NoteBlock(
            id: 'block-1',
            type: 'task',
            delta: [
              {'insert': 'Comprar leite'},
            ],
          ),
        ],
      );
      final sync = _FakeNoteSyncHandle();
      final session = NoteEditorSession(
        noteId: 'note-1',
        controller: controller,
        syncSession: sync,
      );
      final taskController = NoteTaskController((_) async => session);

      await taskController.complete(
        const NoteTask(
          noteId: 'note-1',
          blockId: 'block-1',
          title: 'Comprar leite',
        ),
      );

      expect(
        _isComplete(controller),
        isTrue,
      );
      expect(sync.flushCalls, 1);
      await session.dispose();
    },
  );

  test('does not mutate a note task without edit permission', () async {
    final controller = NoteEditorController(
      userId: 'user-1',
      noteId: 'note-1',
      blocks: [
        NoteBlock(
          id: 'block-1',
          type: 'task',
          delta: [
            {'insert': 'Comprar leite'},
          ],
        ),
      ],
    );
    final sync = _FakeNoteSyncHandle(captureLocalOperations: false);
    final session = NoteEditorSession(
      noteId: 'note-1',
      controller: controller,
      syncSession: sync,
    );
    final taskController = NoteTaskController((_) async => session);

    await expectLater(
      taskController.complete(
        const NoteTask(
          noteId: 'note-1',
          blockId: 'block-1',
          title: 'Comprar leite',
        ),
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      _isComplete(controller),
      isFalse,
    );
    expect(sync.flushCalls, 0);
    await session.dispose();
  });
}

class _FakeNoteSyncHandle implements NoteEditorSyncHandle {
  _FakeNoteSyncHandle({this.captureLocalOperations = true});

  @override
  bool captureLocalOperations;

  int flushCalls = 0;

  @override
  NoteSessionStatus status = NoteSessionStatus.ready;

  @override
  Stream<NoteSessionStatus> get statusChanges => const Stream.empty();

  @override
  Stream<bool> get captureLocalOperationsChanges => const Stream.empty();

  @override
  void setCaptureLocalOperations(bool value) {
    captureLocalOperations = value;
  }

  @override
  Future<void> start() async {}

  @override
  Future<bool> reconcileRemote() async => true;

  @override
  Future<void> flushNow() async {
    flushCalls++;
  }

  @override
  Future<void> dispose() async {}
}

bool _isComplete(NoteEditorController controller) =>
    const NoteAppFlowyCodec()
        .toBlocks(controller.editorState.document)
        .single
        .metadata['isCompleted'] ==
    true;

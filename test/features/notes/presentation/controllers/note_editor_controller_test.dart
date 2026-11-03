import 'dart:async';
import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/attachments/domain/attachment_upload.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_codec.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_controller.dart';
import 'package:supanotes/features/notes/editor/document/note_blocks.dart';
import 'package:supanotes/features/tasks/domain/task_schedule_identity.dart';

class _Uploader implements AttachmentUploader {
  _Uploader(this.result);

  final Future<AttachmentUploadResult> result;

  @override
  Future<AttachmentUploadResult> upload({
    required String id,
    required String noteId,
    required File file,
    required String mimeType,
  }) => result;
}

NoteBlock _b(
  String id,
  String type, [
  String text = '',
  Map<String, dynamic> metadata = const {},
]) => NoteBlock(
  id: id,
  type: type,
  delta: [
    if (text.isNotEmpty) {'insert': text},
  ],
  metadata: metadata,
);

NoteEditorController _controller(List<NoteBlock>? blocks) =>
    NoteEditorController(userId: 'user-1', noteId: 'note-1', blocks: blocks);

List<NoteBlock> _blocks(NoteEditorController controller) =>
    const NoteAppFlowyCodec().toBlocks(controller.editorState.document);

NoteBlock _block(NoteEditorController controller, String id) =>
    _blocks(controller).singleWhere((block) => block.id == id);

void _caret(NoteEditorController controller, String id, [int offset = 0]) {
  controller.focusBlock(id);
  final selection = controller.editorState.selection!;
  controller.editorState.selection = Selection.collapsed(
    selection.end.copyWith(offset: offset),
  );
}

void main() {
  test('a new note starts with the canonical init paragraph', () async {
    for (final blocks in [null, const <NoteBlock>[]]) {
      final controller = _controller(blocks);
      expect(_blocks(controller).single.id, 'init');
      expect(_blocks(controller).single.type, 'paragraph');
      await controller.dispose();
    }
  });

  test('task mutations preserve the task indentation', () async {
    final controller = _controller([
      _b('parent', 'task', 'Parent task'),
      _b('t', 'task', 'Nested task', {
        'indent': 1,
        'dueDate': '2026-07-31T10:00:00.000Z',
      }),
    ]);

    await controller.updateTaskMetadataInEditor('t', reminder: '10m');
    expect(_block(controller, 't').indent, 1);
    expect(_block(controller, 't').metadata['reminder'], '10m');

    await controller.completeTaskInEditor(
      't',
      now: DateTime.utc(2026, 7, 31, 12),
    );
    expect(_block(controller, 't').indent, 1);
    expect(_block(controller, 't').metadata['isCompleted'], isTrue);

    await controller.reopenTaskInEditor('t');
    expect(_block(controller, 't').indent, 1);
    expect(_block(controller, 't').metadata['isCompleted'], isFalse);
    await controller.dispose();
  });

  test(
    'completes the current occurrence when the stored date is stale',
    () async {
      final controller = _controller([
        _b('t', 'task', 'Daily task', {
          'dueDate': '2026-07-01T09:00:00.000',
          'hasTime': true,
          'recurrenceRule': 'daily',
        }),
      ]);

      final result = await controller.completeTaskInEditor(
        't',
        now: DateTime(2026, 7, 4, 12),
      );

      expect(result?.scheduledAt, DateTime(2026, 7, 4, 9));
      expect(result?.nextDue, DateTime(2026, 7, 5, 9));
      final metadata = _block(controller, 't').metadata;
      expect(metadata['dueDate'], '2026-07-01T09:00:00.000');
      expect(
        (metadata['completions'] as Map).keys,
        contains(scheduledAtKey(DateTime(2026, 7, 4, 9), hasTime: true)),
      );
      await controller.dispose();
    },
  );

  test('early recurring completions keep the anchor', () async {
    final controller = _controller([
      _b('t', 'task', 'Weekly task', {
        'dueDate': '2026-08-12T09:00:00.000',
        'hasTime': true,
        'recurrenceRule': 'weekly',
      }),
    ]);

    final first = await controller.completeTaskInEditor(
      't',
      now: DateTime(2026, 8, 10, 14),
    );
    final second = await controller.completeTaskInEditor(
      't',
      now: DateTime(2026, 8, 10, 15),
    );

    expect(first?.scheduledAt, DateTime(2026, 8, 12, 9));
    expect(first?.nextDue, DateTime(2026, 8, 19, 9));
    expect(second?.scheduledAt, DateTime(2026, 8, 12, 9));
    final metadata = _block(controller, 't').metadata;
    expect(metadata['dueDate'], '2026-08-12T09:00:00.000');
    expect((metadata['completions'] as Map).keys, ['2026-08-12T09:00:00.000']);
    await controller.dispose();
  });

  test('stores a non-recurring completion instant in UTC', () async {
    final controller = _controller([
      _b('t', 'task', 'One-time task', {
        'dueDate': '2026-08-12T09:00:00.000',
        'hasTime': true,
      }),
    ]);

    final now = DateTime(2026, 8, 10, 14);
    await controller.completeTaskInEditor('t', now: now);

    final metadata = _block(controller, 't').metadata;
    expect(metadata['isCompleted'], isTrue);
    expect(metadata['dueDate'], '2026-08-12T09:00:00.000');
    expect(metadata['lastCompletedAt'], now.toUtc().toIso8601String());
    await controller.dispose();
  });

  test('reopens an occurrence whatever its old UTC key looks like', () async {
    final controller = _controller([
      _b('t', 'task', 'All-day task', {
        'dueDate': '2026-08-12T00:00:00.000',
        'hasTime': false,
        'recurrenceRule': 'weekly',
        'completions': {'2026-08-12T03:00:00.000Z': '2026-08-10T14:00:00.000Z'},
      }),
    ]);

    await controller.reopenTaskInEditor(
      't',
      scheduledAt: DateTime(2026, 8, 12),
    );

    expect(_block(controller, 't').metadata['completions'], isEmpty);
    await controller.dispose();
  });

  test('deleting the only task leaves an empty paragraph', () async {
    final controller = _controller([_b('t', 'task', 'Única')]);

    await controller.deleteTaskInEditor('t');

    expect(_blocks(controller).single.type, 'paragraph');
    await controller.dispose();
  });

  test('successful upload writes the remote reference to the block', () async {
    final controller = _controller([_b('p', 'paragraph', 'Recibo:')]);
    _caret(controller, 'p', 7);
    final result = AttachmentUploadResult(
      id: 'remote-1',
      noteId: 'note-1',
      fileName: 'receipt.pdf',
      downloadUrl: '/api/v1/attachments/remote-1/content',
      mimeType: 'application/pdf',
      fileSize: 42,
      createdAt: DateTime.utc(2026, 9, 16),
    );

    await controller.attachFileFromPath(
      filePath: 'receipt.pdf',
      mimeType: 'application/pdf',
      uploader: _Uploader(Future.value(result)),
    );

    final blocks = _blocks(controller);
    expect(blocks.map((block) => block.type), [
      'paragraph',
      'attachment',
      'paragraph',
    ]);
    final metadata = blocks[1].metadata;
    expect(metadata['attachmentId'], isNull);
    expect(metadata['url'], result.downloadUrl);
    expect(metadata['fileSize'], 42);
    await controller.dispose();
  });

  test('a failed upload removes its placeholder block', () async {
    final upload = Completer<AttachmentUploadResult>();
    final controller = _controller([_b('p', 'paragraph', 'texto')]);
    _caret(controller, 'p', 5);

    final uploadFuture = controller.attachFileFromPath(
      filePath: 'a.txt',
      mimeType: 'text/plain',
      uploader: _Uploader(upload.future),
    );
    upload.completeError(StateError('upload failed'));
    await expectLater(uploadFuture, throwsStateError);

    expect(
      _blocks(controller).map((block) => block.type),
      isNot(contains('attachment')),
    );
    await controller.dispose();
  });

  test('stale upload failure does not mutate an inactive editor', () async {
    final upload = Completer<AttachmentUploadResult>();
    var active = true;
    final controller = _controller([_b('p', 'paragraph')]);
    _caret(controller, 'p');
    controller.attachMutationGuard(() {
      if (!active) throw StateError('inactive session');
    });

    final uploadFuture = controller.attachFileFromPath(
      filePath: 'attachment.txt',
      mimeType: 'text/plain',
      uploader: _Uploader(upload.future),
    );
    await pumpEventQueue();
    final before = _blocks(controller);
    expect(before.map((block) => block.type), contains('attachment'));

    active = false;
    upload.completeError(StateError('upload failed'));
    await expectLater(uploadFuture, throwsStateError);

    expect(_blocks(controller), before);
    await controller.dispose();
  });
}

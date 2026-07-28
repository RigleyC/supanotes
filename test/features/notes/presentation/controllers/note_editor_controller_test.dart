import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';

void main() {
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
}

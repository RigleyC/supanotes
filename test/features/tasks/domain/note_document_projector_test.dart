import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/domain/note_document_projector.dart';

void main() {
  test('projects the latest reached timed occurrence', () {
    final projector = NoteDocumentProjector(
      now: () => DateTime(2026, 8, 4, 12),
    );

    final result = projector.projectBlocks(
      noteId: 'note-1',
      blocks: [
        {
          'id': 'task-1',
          'type': 'task',
          'metadata': {
            'isCompleted': false,
            'hasTime': true,
            'dueDate': '2026-08-01T09:00:00.000',
            'recurrenceRule': 'daily',
          },
          'content': [
            {'insert': 'Timed daily task'},
          ],
        },
      ],
    );

    expect(result.tasks, hasLength(1));
    expect(result.tasks.single.dueDate, '2026-08-04T09:00:00.000');
  });
}

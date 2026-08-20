import 'package:flutter_test/flutter_test.dart';

import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/share/domain/share_note_index.dart';

NoteModel note({
  required String id,
  required DateTime updatedAt,
  String? permission,
}) => NoteModel(
  id: id,
  userId: 'user-1',
  content: 'Content $id',
  title: 'Title $id',
  excerpt: 'Preview $id',
  favorite: false,
  archived: false,
  createdAt: updatedAt,
  updatedAt: updatedAt,
  permission: permission,
  hasRemoteCopy: true,
  isEmptyDraft: false,
);

void main() {
  test('filters read-only notes and sorts editable notes by update time', () {
    final index = ShareNoteIndex.fromNotes('user-1', [
      note(id: 'old', updatedAt: DateTime(2026, 1, 1)),
      note(id: 'view', updatedAt: DateTime(2026, 1, 3), permission: 'view'),
      note(id: 'new', updatedAt: DateTime(2026, 1, 2)),
    ]);

    expect(index.ownerUserId, 'user-1');
    expect(index.notes.map((note) => note.noteId), ['new', 'old']);
    expect(index.notes.every((note) => note.canEdit), isTrue);
  });

  test('encodes an account-scoped versioned envelope', () {
    final index = ShareNoteIndex.fromNotes('user-1', [
      note(id: 'note-1', updatedAt: DateTime.utc(2026, 1, 1)),
    ]);

    expect(index.toJson(), {
      'schemaVersion': 1,
      'ownerUserId': 'user-1',
      'notes': [
        {
          'noteId': 'note-1',
          'title': 'Title note-1',
          'preview': 'Preview note-1',
          'updatedAt': '2026-01-01T00:00:00.000Z',
          'canEdit': true,
        },
      ],
    });
  });
}

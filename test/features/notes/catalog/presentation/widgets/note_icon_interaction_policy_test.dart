import 'package:flutter_test/flutter_test.dart';

import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/note_icon_interaction_policy.dart';

void main() {
  final editableNote = NoteModel(
    id: 'note-1',
    userId: 'user-1',
    content: 'Nota',
    title: 'Nota',
    favorite: false,
    archived: false,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    hasRemoteCopy: true,
    isEmptyDraft: false,
  );
  final readOnlyNote = NoteModel(
    id: 'note-2',
    userId: 'user-1',
    content: 'Somente leitura',
    title: 'Somente leitura',
    permission: 'view',
    favorite: false,
    archived: false,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    hasRemoteCopy: true,
    isEmptyDraft: false,
  );

  test('allows icon editing only on editable notes with a handler', () {
    expect(
      NoteIconInteractionPolicy.canUseLongPress(
        note: editableNote,
        onEditIcon: () {},
      ),
      isTrue,
    );
    expect(
      NoteIconInteractionPolicy.canUseLongPress(
        note: readOnlyNote,
        onEditIcon: () {},
      ),
      isFalse,
    );
    expect(
      NoteIconInteractionPolicy.canUseLongPress(
        note: editableNote,
        onEditIcon: null,
      ),
      isFalse,
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';

void main() {
  test('NoteModel.title is the field value, not derived from content', () {
    final model = NoteModel(
      id: '1',
      userId: 'u',
      content: 'some content that is NOT the title',
      title: 'From Node',
      
      favorite: false,
      archived: false,
      createdAt: DateTime(2026, 7, 6),
      updatedAt: DateTime(2026, 7, 6),
    );

    expect(model.title, 'From Node');
  });

  test('NoteModel.copyWith preserves title when title is not passed', () {
    final model = NoteModel(
      id: '1',
      userId: 'u',
      content: 'body',
      title: 'Kept Title',
      
      favorite: false,
      archived: false,
      createdAt: DateTime(2026, 7, 6),
      updatedAt: DateTime(2026, 7, 6),
    );

    final updated = model.copyWith(content: 'new body');
    expect(updated.title, 'Kept Title');
    expect(updated.content, 'new body');
  });
}

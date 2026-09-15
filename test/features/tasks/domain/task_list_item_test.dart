import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/domain/task_list_item.dart';

void main() {
  test('constructs each task list union with a non-null source', () {
    const note = NoteTask(noteId: 'n1', blockId: 'b1', title: 'Note task');
    const item = TaskListItem.note(note);
    expect(item.isNote, isTrue);
    expect(item.note, same(note));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/domain/task_notification_entry.dart';

void main() {
  test('compares equivalent scheduled wall-clock representations equally', () {
    final local = TaskNotificationEntry.standalone(
      id: 'task-1',
      title: 'All-day task',
      dueDate: DateTime(2026, 8, 12),
      hasTime: false,
      reminder: '9am',
    );
    final utc = TaskNotificationEntry.standalone(
      id: 'task-1',
      title: 'All-day task',
      dueDate: DateTime.utc(2026, 8, 12, 3),
      hasTime: false,
      reminder: '9am',
    );

    expect(local, utc);
    expect(local.hashCode, utc.hashCode);
  });

  test('does not merge different scheduled dates', () {
    final first = TaskNotificationEntry.standalone(
      id: 'task-1',
      title: 'Task',
      dueDate: DateTime(2026, 8, 12),
      hasTime: false,
      reminder: '9am',
    );
    final second = TaskNotificationEntry.standalone(
      id: 'task-1',
      title: 'Task',
      dueDate: DateTime(2026, 8, 13),
      hasTime: false,
      reminder: '9am',
    );

    expect(first, isNot(second));
  });

  test('keeps note identity in equality and hashing', () {
    final first = TaskNotificationEntry.note(
      id: 'task-1',
      title: 'Task',
      dueDate: DateTime(2026, 8, 12),
      hasTime: false,
      reminder: '9am',
      noteId: 'note-1',
    );
    final second = TaskNotificationEntry.note(
      id: 'task-1',
      title: 'Task',
      dueDate: DateTime(2026, 8, 12),
      hasTime: false,
      reminder: '9am',
      noteId: 'note-2',
    );

    expect(first, isNot(second));
    expect(first.hashCode, isNot(second.hashCode));
    expect(first.sourceKey, 'note:note-1:task-1');
    expect(second.sourceKey, 'note:note-2:task-1');
  });

  test('rejects a note entry without a non-empty note ID', () {
    expect(
      () => TaskNotificationEntry.note(
        id: 'task-1',
        title: 'Task',
        dueDate: DateTime(2026, 8, 12),
        hasTime: false,
        reminder: '9am',
        noteId: ' ',
      ),
      throwsArgumentError,
    );
  });
}

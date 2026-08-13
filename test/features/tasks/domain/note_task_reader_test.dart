import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/domain/note_task_reader.dart';

void main() {
  test('reads an open task from an effective document snapshot', () {
    final document = jsonEncode({
      'schemaVersion': 1,
      'blocks': [
        {
          'id': 'task-1',
          'type': 'task',
          'delta': [
            {'insert': 'Pay rent'},
          ],
          'metadata': {
            'dueDate': '2099-01-02T10:00:00.000Z',
            'hasTime': true,
            'reminder': 'at_time',
            'isCompleted': false,
          },
        },
      ],
    });

    final entries = const NoteTaskReader().read(document);

    expect(entries, hasLength(1));
    expect(entries.single.id, 'task-1');
    expect(entries.single.title, 'Pay rent');
    expect(entries.single.reminder, 'at_time');
  });

  test('does not read a completed recurring occurrence as open', () {
    final document = jsonEncode({
      'schemaVersion': 1,
      'blocks': [
        {
          'id': 'task-1',
          'type': 'task',
          'delta': [
            {'insert': 'Daily task'},
          ],
          'metadata': {
            'dueDate': '2020-01-01T09:00:00.000Z',
            'hasTime': false,
            'recurrenceRule': 'daily',
            'completions': {
              '2020-01-01T09:00:00.000Z': '2020-01-01T08:00:00.000Z',
            },
          },
        },
      ],
    });

    expect(const NoteTaskReader().read(document), hasLength(1));
  });

  test('reads tasks from a persisted snapshot with leaked text mutations', () {
    final document = jsonEncode({
      'schemaVersion': 1,
      'blocks': [
        {
          'id': 'task-1',
          'type': 'task',
          'delta': [
            {'insert': 'Persisted task'},
            {'delete': 14},
          ],
          'metadata': {
            'dueDate': '2099-01-02T10:00:00.000Z',
            'hasTime': true,
            'isCompleted': false,
          },
        },
      ],
    });

    final entries = const NoteTaskReader().read(document);

    expect(entries, hasLength(1));
    expect(entries.single.title, 'Persisted task');
  });

  test('reads tasks from a persisted snapshot with empty delta operations', () {
    final document = jsonEncode({
      'schemaVersion': 1,
      'blocks': [
        {
          'id': 'heading-1',
          'type': 'header1',
          'delta': [{}],
        },
        {
          'id': 'task-1',
          'type': 'task',
          'delta': [
            {'insert': 'Persisted task'},
          ],
          'metadata': {
            'dueDate': '2099-01-02T10:00:00.000Z',
            'hasTime': true,
            'isCompleted': false,
          },
        },
      ],
    });

    expect(const NoteTaskReader().read(document), hasLength(1));
  });
}

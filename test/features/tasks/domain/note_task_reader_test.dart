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
            'dueDate': '2099-01-02T10:00:00.000',
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
            'dueDate': '2020-01-01T09:00:00.000',
            'hasTime': false,
            'recurrenceRule': 'daily',
            'completions': {
              '2020-01-01T09:00:00.000': '2020-01-01T08:00:00.000Z',
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
            'dueDate': '2099-01-02T10:00:00.000',
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
            'dueDate': '2099-01-02T10:00:00.000',
            'hasTime': true,
            'isCompleted': false,
          },
        },
      ],
    });

    expect(const NoteTaskReader().read(document), hasLength(1));
  });

  test('uses the next future occurrence for an overdue reminder', () {
    final document = jsonEncode({
      'schemaVersion': 1,
      'blocks': [
        {
          'id': 'task-1',
          'type': 'task',
          'delta': [
            {'insert': 'Weekly task'},
          ],
          'metadata': {
            'dueDate': '2026-08-05T09:00:00.000',
            'hasTime': true,
            'recurrenceRule': 'weekly',
            'reminder': 'at_time',
          },
        },
      ],
    });

    final entries = NoteTaskReader(
      clock: () => DateTime(2026, 8, 10, 10),
    ).read(document);

    expect(entries.single.dueDate, DateTime(2026, 8, 12, 9));
  });

  test('keeps a same-day all-day reminder that is still in the future', () {
    final document = jsonEncode({
      'schemaVersion': 1,
      'blocks': [
        {
          'id': 'task-1',
          'type': 'task',
          'delta': [
            {'insert': 'All-day task'},
          ],
          'metadata': {
            'dueDate': '2026-08-05T00:00:00.000',
            'hasTime': false,
            'recurrenceRule': 'weekly',
            'reminder': '9am',
          },
        },
      ],
    });

    final entries = NoteTaskReader(
      clock: () => DateTime(2026, 8, 12, 8),
    ).read(document);

    expect(entries.single.dueDate, DateTime(2026, 8, 12));
  });

  test('matches all-day completion keys by calendar date', () {
    final document = jsonEncode({
      'schemaVersion': 1,
      'blocks': [
        {
          'id': 'task-1',
          'type': 'task',
          'delta': [
            {'insert': 'All-day task'},
          ],
          'metadata': {
            'dueDate': '2026-08-12T00:00:00.000',
            'hasTime': false,
            'recurrenceRule': 'weekly',
            'completions': {
              '2026-08-12T00:00:00.000': '2026-08-10T14:00:00.000Z',
            },
            'reminder': '9am',
          },
        },
      ],
    });

    final entries = NoteTaskReader(
      clock: () => DateTime(2026, 8, 10, 10),
    ).read(document);

    expect(entries.single.dueDate, DateTime(2026, 8, 19));
  });

  test('allows two early completions before the anchor date', () {
    final document = jsonEncode({
      'schemaVersion': 1,
      'blocks': [
        {
          'id': 'task-1',
          'type': 'task',
          'delta': [
            {'insert': 'Weekly task'},
          ],
          'metadata': {
            'dueDate': '2026-08-12T09:00:00.000',
            'hasTime': true,
            'recurrenceRule': 'weekly',
            'completions': {
              '2026-08-12T09:00:00.000': '2026-08-10T14:00:00.000Z',
              '2026-08-19T09:00:00.000': '2026-08-10T15:00:00.000Z',
            },
            'reminder': 'at_time',
          },
        },
      ],
    });

    final entries = NoteTaskReader(
      clock: () => DateTime(2026, 8, 10, 16),
    ).read(document);

    expect(entries.single.dueDate, DateTime(2026, 8, 26, 9));
  });
}

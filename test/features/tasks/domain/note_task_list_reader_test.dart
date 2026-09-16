import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/domain/note_task_list_reader.dart';

Map<String, dynamic> _taskBlock({
  required String id,
  required String title,
  String? dueDate,
  bool hasTime = false,
  String? recurrenceRule,
  bool isCompleted = false,
  Map<String, String>? completions,
}) => {
  'id': id,
  'type': 'task',
  'delta': [
    {'insert': title},
  ],
  'metadata': {
    if (dueDate != null) 'dueDate': dueDate,
    'hasTime': hasTime,
    if (recurrenceRule != null) 'recurrenceRule': recurrenceRule,
    if (completions != null) 'completions': completions,
    'isCompleted': isCompleted,
  },
};

String _document(List<Map<String, dynamic>> blocks) => jsonEncode({
  'schemaVersion': 1,
  'blocks': blocks,
});

void main() {
  test('keeps the overdue recurring occurrence visible in the list', () {
    final tasks =
        const NoteTaskListReader(
          clock: _fixedNow,
        ).read(
          noteId: 'note-1',
          noteTitle: 'Agenda',
          documentJson: _document([
            _taskBlock(
              id: 'block-1',
              title: 'Revisar contrato',
              dueDate: '2026-09-01T09:00:00.000',
              hasTime: true,
              recurrenceRule: 'weekly',
            ),
          ]),
          hideCompleted: true,
        );

    expect(tasks, hasLength(1));
    expect(tasks.single.dueDate, DateTime(2026, 9, 15, 9));
    expect(tasks.single.noteId, 'note-1');
    expect(tasks.single.blockId, 'block-1');
  });

  test('keeps an undated task and excludes completed tasks', () {
    final tasks =
        const NoteTaskListReader(
          clock: _fixedNow,
        ).read(
          noteId: 'note-1',
          noteTitle: 'Agenda',
          documentJson: _document([
            _taskBlock(id: 'open', title: 'Sem data'),
            _taskBlock(id: 'done', title: 'Concluída', isCompleted: true),
          ]),
          hideCompleted: true,
        );

    expect(tasks.map((task) => task.blockId), ['open']);
    expect(tasks.single.dueDate, isNull);
  });

  test('can include completed blocks when the note preference allows them', () {
    final tasks =
        const NoteTaskListReader(
          clock: _fixedNow,
        ).read(
          noteId: 'note-1',
          noteTitle: 'Agenda',
          documentJson: _document([
            _taskBlock(id: 'done', title: 'Concluída', isCompleted: true),
          ]),
          hideCompleted: false,
        );

    expect(tasks, hasLength(1));
    expect(tasks.single.isCompleted, isTrue);
  });
}

DateTime _fixedNow() => DateTime(2026, 9, 15, 10);

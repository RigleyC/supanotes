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
        );

    expect(tasks, hasLength(1));
    expect(tasks.single.dueDate, DateTime(2026, 9, 15, 9));
    expect(tasks.single.noteId, 'note-1');
    expect(tasks.single.blockId, 'block-1');
  });

  test('keeps undated and completed task rows for the global task list', () {
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
        );

    expect(tasks.map((task) => task.blockId), ['open', 'done']);
    expect(
      tasks.firstWhere((task) => task.blockId == 'open').dueDate,
      isNull,
    );
  });

  test('includes completed blocks for the global task list', () {
    final tasks =
        const NoteTaskListReader(
          clock: _fixedNow,
        ).read(
          noteId: 'note-1',
          noteTitle: 'Agenda',
          documentJson: _document([
            _taskBlock(id: 'open', title: 'Em aberto'),
            _taskBlock(id: 'done', title: 'Concluída', isCompleted: true),
          ]),
        );

    expect(tasks.map((task) => task.blockId), ['open', 'done']);
    expect(tasks.last.isCompleted, isTrue);
  });
}

DateTime _fixedNow() => DateTime(2026, 9, 15, 10);

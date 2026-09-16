import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/editor/document/note_task_editor_commands.dart';
import 'package:super_editor/super_editor.dart';

void main() {
  test('repeating the same metadata update is idempotent', () {
    final node = TaskNode(
      id: 'task-1',
      text: AttributedText('Pay'),
      isComplete: false,
      metadata: const {
        'dueDate': '2026-09-18T09:00:00.000',
        'hasTime': true,
        'reminder': '10m',
      },
    );
    const commands = NoteTaskEditorCommands();

    final unchanged = commands.updateMetadata(
      node,
      dueDate: DateTime(2026, 9, 18, 9),
      hasTime: true,
      reminder: '10m',
    );

    expect(identical(unchanged, node), isTrue);
  });

  test('changing schedule clears completion history', () {
    final node = TaskNode(
      id: 'task-1',
      text: AttributedText('Pay'),
      isComplete: false,
      metadata: const {
        'dueDate': '2026-09-18T09:00:00.000',
        'hasTime': true,
        'recurrenceRule': 'weekly',
        'completions': {'2026-09-18T09:00:00.000': '2026-09-16T12:00:00Z'},
      },
    );

    final updated = const NoteTaskEditorCommands().updateMetadata(
      node,
      recurrence: 'daily',
    );

    expect(updated.metadata['recurrenceRule'], 'daily');
    expect(updated.metadata.containsKey('completions'), isFalse);
  });

  test('completion parses malformed completion metadata as empty input', () {
    final node = TaskNode(
      id: 'task-1',
      text: AttributedText('Pay'),
      isComplete: false,
      metadata: const {
        'dueDate': '2026-09-16T09:00:00.000',
        'hasTime': true,
        'recurrenceRule': 'daily',
        'completions': {'not-a-date': 42},
      },
    );

    final mutation = const NoteTaskEditorCommands().complete(
      node,
      now: DateTime(2026, 9, 16, 12),
    );

    expect(mutation.result.scheduledAt, DateTime(2026, 9, 16, 9));
    expect(
      mutation.node.metadata['completions'],
      containsPair('2026-09-16T09:00:00.000', '2026-09-16T15:00:00.000Z'),
    );
  });
}

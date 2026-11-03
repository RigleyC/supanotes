import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/editor/document/note_task_editor_commands.dart';

void main() {
  test('repeating the same metadata update is idempotent', () {
    const NoteTaskState task = (
      isComplete: false,
      metadata: {
        'dueDate': '2026-09-18T09:00:00.000',
        'hasTime': true,
        'reminder': '10m',
      },
    );

    final unchanged = const NoteTaskEditorCommands().updateMetadataState(
      task,
      dueDate: DateTime(2026, 9, 18, 9),
      hasTime: true,
      reminder: '10m',
    );

    expect(unchanged, isNull);
  });

  test('changing schedule clears completion history', () {
    const NoteTaskState task = (
      isComplete: false,
      metadata: {
        'dueDate': '2026-09-18T09:00:00.000',
        'hasTime': true,
        'recurrenceRule': 'weekly',
        'completions': {'2026-09-18T09:00:00.000': '2026-09-16T12:00:00Z'},
      },
    );

    final updated = const NoteTaskEditorCommands().updateMetadataState(
      task,
      recurrence: 'daily',
    )!;

    expect(updated.metadata['recurrenceRule'], 'daily');
    expect(updated.metadata.containsKey('completions'), isFalse);
  });

  test('completion parses malformed completion metadata as empty input', () {
    const NoteTaskState task = (
      isComplete: false,
      metadata: {
        'dueDate': '2026-09-16T09:00:00.000',
        'hasTime': true,
        'recurrenceRule': 'daily',
        'completions': {'not-a-date': 42},
      },
    );

    final (state, result) = const NoteTaskEditorCommands().completeState(
      task,
      now: DateTime(2026, 9, 16, 12),
    );

    expect(result.scheduledAt, DateTime(2026, 9, 16, 9));
    expect(
      state.metadata['completions'],
      // Completion time is stored in UTC; derive it from the local clock so
      // the expectation holds in every machine time zone.
      containsPair(
        '2026-09-16T09:00:00.000',
        DateTime(2026, 9, 16, 12).toUtc().toIso8601String(),
      ),
    );
  });
}

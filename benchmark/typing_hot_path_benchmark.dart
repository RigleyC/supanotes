// Measures the work the app does on every autosave while the user types.
//
// The editor persists the materialized document roughly every 1.2s. Each save
// writes `notes` and `local_note_documents`, which re-runs every Drift stream
// that reads those tables: the notes catalog, the reminder source and (when
// the Tasks tab is alive) the task list. This benchmark seeds a realistic
// library, keeps those consumers subscribed, and times a burst of saves to a
// single note until every consumer has observed each save.
//
// Run with:
//   flutter test benchmark/typing_hot_path_benchmark.dart
import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/tasks/application/task_list_providers.dart';
import 'package:supanotes/features/tasks/domain/note_task_notification_source.dart';

const _userId = 'user-1';
const _noteCount = 200;
const _paragraphsPerNote = 30;
const _tasksPerNote = 10;
const _saves = 20;

/// Comma-separated consumers to keep subscribed (for profiling one at a time),
/// e.g. `--dart-define=CONSUMERS=catalog`.
const _consumers = String.fromEnvironment(
  'CONSUMERS',
  defaultValue: 'catalog,reminder,tasks',
);
final Set<String> _enabled = _consumers.split(',').toSet();
final bool _catalog = _enabled.contains('catalog');
final bool _reminder = _enabled.contains('reminder');
final bool _tasks = _enabled.contains('tasks');

void main() {
  test('typing hot path: autosave fan-out', () async {
    final database = AppDatabase.test();
    final now = DateTime.utc(2026, 9, 15, 10);
    await _seed(database, now);

    var catalogEmissions = 0;
    var reminderEmissions = 0;
    var taskListEmissions = 0;
    bool observed(int before, int after, {required bool enabled}) =>
        !enabled || after > before;

    // Catalog consumer, mapped the same way activeNotesProvider maps rows.
    final catalogSub = !_catalog
        ? null
        : database.notesDao
              .watchAllActiveNotes(_userId)
              .map((rows) => rows.map(NoteModel.fromQueryResult).toList())
              .listen((_) => catalogEmissions++);

    // Reminder consumer (always alive in the app shell).
    final reminderSub = !_reminder
        ? null
        : NoteTaskNotificationSource(
            database,
            clock: () => now,
          ).watchOpenTasks(_userId).listen((_) => reminderEmissions++);

    // Task list consumer (alive while the Tasks tab is in the tree).
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        currentUserIdProvider.overrideWithValue(_userId),
        taskListClockProvider.overrideWithValue(TaskListClock(() => now)),
      ],
    );
    final taskListSub = !_tasks
        ? null
        : container.listen(
            taskListProvider(includeNoteTasks: true),
            (_, next) {
              if (next.hasValue) taskListEmissions++;
            },
            fireImmediately: true,
          );

    Future<void> settle() async {
      // Let Drift re-run queries and every consumer process the results.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    await _waitUntil(
      () =>
          observed(0, catalogEmissions, enabled: _catalog) &&
          observed(0, reminderEmissions, enabled: _reminder) &&
          observed(0, taskListEmissions, enabled: _tasks),
    );
    await settle();

    final stopwatch = Stopwatch()..start();
    for (var save = 0; save < _saves; save++) {
      final catalogBefore = catalogEmissions;
      final reminderBefore = reminderEmissions;
      final taskListBefore = taskListEmissions;
      final document = _document('note-0', edit: save + 1);
      await database.noteOperationsDao.saveMaterializedDocument(
        noteId: 'note-0',
        documentJson: document.json,
        content: document.content,
        excerpt: document.content.substring(0, 200),
        updatedAt: now.add(Duration(seconds: save + 1)),
      );
      await _waitUntil(
        () =>
            observed(catalogBefore, catalogEmissions, enabled: _catalog) &&
            observed(reminderBefore, reminderEmissions, enabled: _reminder) &&
            observed(taskListBefore, taskListEmissions, enabled: _tasks),
      );
      await settle();
    }
    stopwatch.stop();

    final perSave = stopwatch.elapsedMicroseconds / _saves / 1000;
    // A benchmark reports its result on stdout.
    // ignore: avoid_print
    print(
      'BENCHMARK typing_hot_path consumers=$_consumers notes=$_noteCount '
      'saves=$_saves '
      'total=${stopwatch.elapsedMilliseconds}ms '
      'perSave=${perSave.toStringAsFixed(2)}ms',
    );

    taskListSub?.close();
    container.dispose();
    await catalogSub?.cancel();
    await reminderSub?.cancel();
    await database.close();
  }, timeout: const Timeout(Duration(minutes: 5)));
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Consumers did not observe the save');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

Future<void> _seed(AppDatabase database, DateTime now) async {
  for (var n = 0; n < _noteCount; n++) {
    final id = 'note-$n';
    final document = _document(id, edit: 0);
    await database.notesDao.createNote(
      NotesCompanion.insert(
        id: id,
        userId: _userId,
        content: document.content,
        excerpt: Value(document.content.substring(0, 200)),
        createdAt: now,
        updatedAt: now.subtract(Duration(minutes: n)),
        hasRemoteCopy: const Value(true),
      ),
    );
    await database.noteOperationsDao.upsertNoteDocument(
      LocalNoteDocumentsCompanion.insert(
        noteId: id,
        revision: 1,
        documentJson: document.json,
        updatedAt: now,
        materializedDocumentJson: Value(document.json),
        materializedUpdatedAt: Value(now),
      ),
    );
  }
}

({String json, String content}) _document(String noteId, {required int edit}) {
  final blocks = <Map<String, dynamic>>[];
  final content = StringBuffer();
  for (var p = 0; p < _paragraphsPerNote; p++) {
    final text =
        'Paragraph $p of $noteId (edit $edit). Lorem ipsum dolor sit amet, '
        'consectetur adipiscing elit, sed do eiusmod tempor incididunt.';
    blocks.add({
      'id': '$noteId-p$p',
      'type': 'paragraph',
      'delta': [
        {'insert': text},
      ],
    });
    content.writeln(text);
  }
  for (var t = 0; t < _tasksPerNote; t++) {
    final text = 'Task $t of $noteId';
    blocks.add({
      'id': '$noteId-t$t',
      'type': 'task',
      'delta': [
        {'insert': text},
      ],
      'metadata': {
        'dueDate': '2099-01-0${(t % 9) + 1}T10:00:00.000',
        'hasTime': true,
        'reminder': 'at_time',
        'isCompleted': false,
      },
    });
    content.writeln(text);
  }
  return (
    json: jsonEncode({'schemaVersion': 1, 'blocks': blocks}),
    content: content.toString().trimRight(),
  );
}

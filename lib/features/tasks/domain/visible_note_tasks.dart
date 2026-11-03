import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supanotes/core/database/daos/note_operations_dao.dart';
import 'package:supanotes/core/database/daos/notes_dao.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/tasks/domain/note_task_reader.dart';

/// The tasks of one note that the current account can see.
class VisibleNoteTasks {
  const VisibleNoteTasks({
    required this.noteId,
    required this.noteTitle,
    required this.tasks,
    this.createdAt,
  });

  final String noteId;
  final String noteTitle;
  final List<ParsedNoteTask> tasks;
  final DateTime? createdAt;
}

/// Streams the tasks of every note visible to [userId], read from the
/// `note_tasks` projection.
///
/// Saves that change neither a task block nor a note title produce identical
/// rows and are dropped before any metadata is interpreted, so typing in a
/// paragraph does not re-run reminders or rebuild the Tasks list.
Stream<List<VisibleNoteTasks>> watchVisibleNoteTasks(
  AppDatabase database,
  String userId, {
  bool withNoteTitle = true,
}) {
  return database.noteOperationsDao
      .watchVisibleNoteTasks(userId, withNoteTitle: withNoteTitle)
      .distinct(listEquals)
      .map(groupVisibleNoteTasks);
}

/// Groups projected rows by note and interprets each task's metadata.
///
/// A note whose document could not be read is left out (and reported once),
/// so one damaged note never hides every other task or stops reminders.
List<VisibleNoteTasks> groupVisibleNoteTasks(List<VisibleNoteTaskRow> rows) {
  final result = <VisibleNoteTasks>[];
  String? currentNoteId;
  late List<ParsedNoteTask> currentTasks;
  for (final row in rows) {
    final invalidReason = row.invalidReason;
    if (invalidReason != null) {
      _reportUnreadable(row.noteId, invalidReason);
      continue;
    }
    if (row.noteId != currentNoteId) {
      currentNoteId = row.noteId;
      currentTasks = <ParsedNoteTask>[];
      result.add(
        VisibleNoteTasks(
          noteId: row.noteId,
          noteTitle: deriveNoteTitle(row.noteFirstLine),
          tasks: currentTasks,
          createdAt: row.noteCreatedAt,
        ),
      );
    }
    currentTasks.add(
      parseNoteTaskBlock(
        row.blockId,
        row.title,
        jsonDecode(row.metadataJson) as Map<String, dynamic>,
      ),
    );
  }
  return result;
}

final _reportedUnreadable = <String>{};

void _reportUnreadable(String noteId, String reason) {
  if (!_reportedUnreadable.add('$noteId:$reason')) return;
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: FormatException(
        'Note $noteId has an unreadable document: $reason',
      ),
      library: 'supanotes tasks',
      context: ErrorDescription('while listing the tasks of every note'),
      silent: true,
    ),
  );
}

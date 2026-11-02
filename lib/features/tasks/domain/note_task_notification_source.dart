import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/tasks/domain/note_task_reader.dart';
import 'package:supanotes/features/tasks/domain/task_notification_entry.dart';
import 'package:supanotes/features/tasks/domain/task_notification_source.dart';
import 'package:supanotes/features/tasks/domain/visible_note_tasks.dart';

/// Reads reminders from the tasks of the notes visible to the account.
///
/// This source intentionally does not consume the task-list provider. The
/// list's "include note tasks" preference is a presentation filter and must
/// not disable reminders for otherwise active local documents.
class NoteTaskNotificationSource implements TaskNotificationSource {
  NoteTaskNotificationSource(this._database, {this.clock});

  final AppDatabase _database;
  final DateTime Function()? clock;

  Stream<List<TaskNotificationEntry>> watchOpenTasks(String userId) {
    // The projection query applies the notes catalog visibility (ownership
    // and current membership), so a shared document cannot become a reminder
    // for an account that no longer has access to it.
    // Reminders do not show the note title, so title edits are not observed.
    final notes = watchVisibleNoteTasks(
      _database,
      userId,
      withNoteTitle: false,
    );
    final reader = NoteTaskReader(clock: clock);
    return Stream.multi((controller) {
      List<VisibleNoteTasks>? latest;

      void emit() {
        final visible = latest;
        if (visible == null) return;
        try {
          controller.add([
            for (final note in visible)
              ...reader.read(note.tasks, noteId: note.noteId),
          ]);
        } on Object catch (error, stackTrace) {
          controller.addError(error, stackTrace);
        }
      }

      final subscription = notes.listen((visible) {
        latest = visible;
        emit();
      }, onError: controller.addError);
      // Occurrences move with the clock even when no note changes.
      final timer = Timer.periodic(const Duration(minutes: 1), (_) => emit());

      controller.onCancel = () async {
        timer.cancel();
        await subscription.cancel();
      };
    });
  }

  @override
  Future<List<TaskNotificationEntry>> readOpenTasks(String userId) async {
    return watchOpenTasks(userId).first;
  }
}

final StreamProvider<List<TaskNotificationEntry>>
noteTaskNotificationSourceProvider =
    StreamProvider.autoDispose<List<TaskNotificationEntry>>((ref) {
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null || userId.isEmpty) return Stream.value(const []);
      return NoteTaskNotificationSource(
        ref.watch(appDatabaseProvider),
      ).watchOpenTasks(userId);
    });

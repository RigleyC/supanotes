import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/tasks/domain/note_task_reader.dart';
import 'package:supanotes/features/tasks/domain/task_notification_entry.dart';
import 'package:supanotes/features/tasks/domain/task_notification_source.dart';

/// Reads reminders from effective note documents.
///
/// This source intentionally does not consume the task-list provider. The
/// list's "include note tasks" preference is a presentation filter and must
/// not disable reminders for otherwise active local documents.
class NoteTaskNotificationSource implements TaskNotificationSource {
  NoteTaskNotificationSource(this._database, {this.clock});

  final AppDatabase _database;
  final DateTime Function()? clock;

  Stream<List<TaskNotificationEntry>> watchOpenTasks(String userId) {
    // Materialized documents are shared local cache rows, so they must be
    // intersected with the same effective note selection used by the notes
    // list. That selection enforces ownership and current membership before a
    // document can become a reminder for this account.
    final notes = _database.notesDao.watchAllActiveNotes(userId);
    final documents = _database.noteOperationsDao.watchMaterializedDocuments();
    final reader = NoteTaskReader(clock: clock);
    return Stream.multi((controller) {
      var latestAuthorizedNoteIds = const <String>{};
      var latestDocuments = const <LocalNoteDocumentData>[];
      var notesReady = false;
      var documentsReady = false;

      void emit() {
        if (!notesReady || !documentsReady) return;
        controller.add([
          for (final document in latestDocuments)
            if (latestAuthorizedNoteIds.contains(document.noteId) &&
                document.materializedDocumentJson != null)
              ...reader.read(
                document.materializedDocumentJson!,
                noteId: document.noteId,
              ),
        ]);
      }

      // One autosave writes both `notes` and `local_note_documents`, so both
      // watched queries re-run for the same change. Coalescing them into one
      // event-loop turn avoids rebuilding every reminder twice per save.
      Timer? pendingEmit;
      void scheduleEmit() {
        if (pendingEmit != null) return;
        pendingEmit = Timer(Duration.zero, () {
          pendingEmit = null;
          try {
            emit();
          } on Object catch (error, stackTrace) {
            // A malformed document must surface on the stream instead of
            // escaping as an uncaught timer error.
            controller.addError(error, stackTrace);
          }
        });
      }

      final notesSubscription = notes.listen((authorizedNotes) {
        latestAuthorizedNoteIds = {
          for (final note in authorizedNotes) note.note.id,
        };
        notesReady = true;
        scheduleEmit();
      }, onError: controller.addError);
      final documentsSubscription = documents.listen((nextDocuments) {
        latestDocuments = nextDocuments;
        documentsReady = true;
        scheduleEmit();
      }, onError: controller.addError);
      final timer = Timer.periodic(const Duration(minutes: 1), (_) => emit());

      controller.onCancel = () async {
        timer.cancel();
        pendingEmit?.cancel();
        await notesSubscription.cancel();
        await documentsSubscription.cancel();
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

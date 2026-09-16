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
    // The materialized-document table is the effective local cache used by
    // the note runtime. The account ID remains part of the source contract so
    // the scheduler always includes it in the platform identity.
    final dao = _database.noteOperationsDao;
    final reader = NoteTaskReader(clock: clock);
    return Stream.multi((controller) {
      var latestDocuments = const <LocalNoteDocumentData>[];

      void emit() {
        controller.add([
          for (final document in latestDocuments)
            if (document.materializedDocumentJson != null)
              ...reader.read(
                document.materializedDocumentJson!,
                noteId: document.noteId,
              ),
        ]);
      }

      final subscription = dao.watchMaterializedDocuments().listen((
        documents,
      ) {
        latestDocuments = documents;
        emit();
      }, onError: controller.addError);
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

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/database/database.dart';

import 'package:supanotes/features/tasks/domain/note_task_reader.dart';
import 'package:supanotes/features/tasks/domain/task_notification_entry.dart';

final StreamProvider<List<TaskNotificationEntry>> noteTaskNotificationSourceProvider =
    StreamProvider.autoDispose<List<TaskNotificationEntry>>((ref) {
      final dao = ref.watch(appDatabaseProvider).noteOperationsDao;
      const reader = NoteTaskReader();
      return Stream.multi((controller) {
        var latestDocuments = const <LocalNoteDocumentData>[];

        void emit() {
          controller.add([
            for (final document in latestDocuments)
              if (document.materializedDocumentJson != null)
                ...reader.read(document.materializedDocumentJson!),
          ]);
        }

        final subscription = dao.watchMaterializedDocuments().listen((
          documents,
        ) {
          latestDocuments = documents;
          emit();
        }, onError: controller.addError);
        final timer = Timer.periodic(const Duration(minutes: 1), (_) => emit());

        ref.onDispose(() {
          timer.cancel();
          subscription.cancel();
        });
      });
    });

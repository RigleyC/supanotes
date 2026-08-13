import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/database/database.dart';

import 'note_task_reader.dart';
import 'task_notification_entry.dart';

final noteTaskNotificationSourceProvider =
    StreamProvider.autoDispose<List<TaskNotificationEntry>>((ref) {
      final dao = ref.watch(appDatabaseProvider).noteOperationsDao;
      const reader = NoteTaskReader();
      return Stream.multi((controller) {
        List<LocalNoteDocumentData> latestDocuments = const [];

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

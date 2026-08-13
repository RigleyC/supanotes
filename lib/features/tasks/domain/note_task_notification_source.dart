import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/database/database.dart';

import 'note_task_reader.dart';
import 'task_notification_entry.dart';

final noteTaskNotificationSourceProvider =
    StreamProvider.autoDispose<List<TaskNotificationEntry>>((ref) {
      final dao = ref.watch(appDatabaseProvider).noteOperationsDao;
      const reader = NoteTaskReader();
      return dao.watchMaterializedDocuments().map((documents) {
        return [
          for (final document in documents)
            if (document.materializedDocumentJson != null)
              ...reader.read(document.materializedDocumentJson!),
        ];
      });
    });

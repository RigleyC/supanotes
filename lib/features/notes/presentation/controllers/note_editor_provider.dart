import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/sync_service.dart';
import 'note_editor_controller.dart';

final noteEditorControllerProvider = Provider.autoDispose
    .family<NoteEditorController, String>((ref, noteId) {
      final userId = ref.watch(currentUserIdProvider)!;
      final syncService = ref.read(syncServiceProvider);
      final controller = NoteEditorController(
        userId: userId,
        database: ref.watch(appDatabaseProvider),
      );
      controller.bind(noteId);

      syncService?.connectNote(
        noteId,
        onReady: (doc, _) {
          controller.attachYjsBridge(doc: doc);
        },
      );

      ref.onDispose(() {
        syncService?.disconnectNote();
        controller.dispose();
      });
      return controller;
    });

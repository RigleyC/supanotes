import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/sync/sync_service.dart';
import 'note_editor_controller.dart';

final noteEditorControllerProvider = Provider.autoDispose
    .family<NoteEditorController, String>((ref, noteId) {
      final userId = ref.watch(currentUserIdProvider)!;
      final syncService = ref.read(syncServiceProvider);
      final controller = NoteEditorController(
        userId: userId,
      );
      controller.bind(noteId);

      var disposed = false;

      final yjsMgr = ref.read(yjsSyncManagerProvider);

      syncService?.connectNote(
        noteId,
        onReady: (doc, sendUpdate) {
          if (disposed) return;
          controller.initFromDoc(
            doc: doc,
            noteId: noteId,
            sendUpdate: sendUpdate,
            onDocChanged: () {
              yjsMgr.projectNodes(noteId);
              // Fire-and-forget: persist is async and serialized internally via
              // _persistLock. The YDoc state is already consistent at this
              // point; this write is a safety net so offline closures don't
              // lose edits. Riverpod's onDispose is sync and cannot await it.
              unawaited(yjsMgr.persist(noteId));
            },
          );
        },
      ).catchError((_) {
        // connectNote errored (e.g., WS failure) — ignore if disposed.
      });

      ref.onDispose(() {
        disposed = true;
        unawaited(controller.dispose().then((_) => syncService?.disconnectNote()));
      });
      return controller;
    });

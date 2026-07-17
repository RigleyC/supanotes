import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/sync/sync_service.dart';
import 'package:supanotes/features/notes/data/attachments_repository.dart';
import 'note_editor_controller.dart';

final noteEditorControllerProvider = Provider.autoDispose
    .family<NoteEditorController, String>((ref, noteId) {
      final userId = ref.watch(currentUserIdProvider)!;
      final syncService = ref.read(syncServiceProvider);
      final attachmentsRepo = ref.read(attachmentsRepositoryProvider);
      final controller = NoteEditorController(
        userId: userId,
        onUploadFile: (id, filePath, mimeType) => attachmentsRepo.upload(
          id: id,
          noteId: noteId,
          file: File(filePath),
          mimeType: mimeType,
        ),
      );
      controller.bind(noteId);

      var disposed = false;

      final yjsMgr = ref.read(yjsSyncManagerProvider);
      Future<void>? lastProjection;

      syncService?.connectNote(noteId).then((doc) {
        if (disposed || doc == null) return;
        controller.initFromDoc(
          doc: doc,
          noteId: noteId,
          onDocChanged: () {
            lastProjection = yjsMgr.projectNodes(noteId);
            // Fire-and-forget: persist is async and serialized internally via
            // _persistLock. The YDoc state is already consistent at this
            // point; this write is a safety net so offline closures don't
            // lose edits. Riverpod's onDispose is sync and cannot await it.
            unawaited(yjsMgr.persist(noteId));
          },
        );
      }).catchError((_) {
        // connectNote errored (e.g., WS failure) — ignore if disposed.
      });

      ref.onDispose(() {
        disposed = true;
        unawaited(
          controller.dispose()
            .then((_) async {
              if (lastProjection != null) {
                await lastProjection;
              }
              await syncService?.disconnectNote();
            })
        );
      });
      return controller;
    });

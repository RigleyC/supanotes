import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
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
      final db = ref.read(appDatabaseProvider);

      // Single flush queue: coalesces multiple events into one project+persist.
      // Chain serializes calls so concurrent flushes (debounce + dispose) never
      // observe different versions of the YDoc.
      Timer? flushDebounce;
      Future<void>? flushChain;
      bool wasLocallyEdited = false;

      Future<void> doFlush() async {
        flushDebounce?.cancel();
        flushDebounce = null;
        final prev = flushChain ?? Future.value();
        flushChain = prev.then((_) async {
          if (disposed) return;
          await yjsMgr.projectNodes(noteId, markDirty: wasLocallyEdited);
          wasLocallyEdited = false;
          await yjsMgr.persist(noteId);
        });
        await flushChain;
      }

      void scheduleFlush() {
        flushDebounce?.cancel();
        flushDebounce = Timer(
          const Duration(milliseconds: 500),
          () {
            if (disposed) return;
            unawaited(doFlush());
          },
        );
      }

      syncService?.connectNote(noteId).then((doc) async {
        if (disposed || doc == null) return;

        // If the relational content is empty but the YDoc has nodes, re-project
        // now so the title/task list is restored without waiting for an edit.
        final existing = await db.notesDao.getNoteById(noteId);
        if (existing?.content.trim().isEmpty ?? true) {
          await yjsMgr.projectNodes(noteId);
        }

        controller.initFromDoc(
          doc: doc,
          noteId: noteId,
          onDocChanged: ({required isRemote}) {
            if (!isRemote) {
              wasLocallyEdited = true;
              syncService.markDirty(noteId);
            }
            scheduleFlush();
          },
          onDocCommitted: (_) {
            scheduleFlush();
          },
        );
      }).catchError((_) {
        // connectNote errored — ignore if disposed.
      });

      ref.onDispose(() {
        disposed = true;
        flushDebounce?.cancel();
        unawaited(
          controller.dispose()
            .then((_) async {
              await doFlush();
              await syncService?.disconnectNote();
            })
        );
      });
      return controller;
    });

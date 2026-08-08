import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/notes/attachments/data/attachments_repository.dart';
import 'package:supanotes/features/notes/catalog/data/notes_repository.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_session.dart';
import 'package:supanotes/features/tasks/domain/task_projection_engine.dart';
import 'note_editor_controller.dart';
import 'note_editor_session.dart';

final _noteEditorSessionOwnerProvider = FutureProvider.autoDispose
    .family<NoteEditorSession, String>((ref, noteId) async {
      final userId = ref.watch(currentUserIdProvider)!;
      final sessionCoordinator = ref.read(noteSessionCoordinatorProvider);
      final notesRepository = ref.watch(notesRepositoryProvider);

      bool isDisposed = false;
      StreamSubscription? permissionSubscription;

      ref.onDispose(() {
        isDisposed = true;
        unawaited(permissionSubscription?.cancel());
        unawaited(sessionCoordinator.close(noteId));
      });

      final note = await notesRepository.watchNoteById(noteId).first;
      if (isDisposed) {
        throw StateError('Provider disposed before session opening');
      }

      final canCaptureLocalOperations = note != null && !note.isReadOnly;

      final session = await sessionCoordinator.open(noteId, () {
        final attachmentsRepo = ref.read(attachmentsRepositoryProvider);
        final controller = NoteEditorController(
          userId: userId,
          noteId: noteId,
          onUploadFile: (id, filePath, mimeType) => attachmentsRepo.upload(
            id: id,
            noteId: noteId,
            file: File(filePath),
            mimeType: mimeType,
          ),
        );

        final database = ref.read(appDatabaseProvider);
        final taskProjectionEngine = TaskProjectionEngine(
          database: database,
        );
        final syncService = ref.read(noteOperationsSyncServiceProvider);

        final syncSession = NoteSyncSession(
          noteId: noteId,
          syncService: syncService,
          document: controller.document,
          editor: controller.editor,
          taskProjectionEngine: taskProjectionEngine,
          userId: userId,
          captureLocalOperations: canCaptureLocalOperations,
        );

        return NoteEditorSession(
          noteId: noteId,
          controller: controller,
          syncSession: syncSession,
        );
      });

      if (isDisposed) {
        unawaited(sessionCoordinator.close(noteId));
        throw StateError('Provider disposed during session opening');
      }

      permissionSubscription = notesRepository.watchNoteById(noteId).listen((
        note,
      ) {
        final canCapture = note != null && !note.isReadOnly;
        session.setCaptureLocalOperations(canCapture);
      });

      return session;
    });

final noteEditorSessionProvider = FutureProvider.autoDispose
    .family<NoteEditorSession, String>((ref, noteId) async {
      final session = await ref.watch(
        _noteEditorSessionOwnerProvider(noteId).future,
      );
      return session;
    });

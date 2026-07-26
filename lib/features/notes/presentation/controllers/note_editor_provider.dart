import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/notes/data/attachments_repository.dart';
import 'package:supanotes/features/notes/domain/note_session_coordinator.dart';
import 'package:supanotes/features/notes/domain/note_sync_session.dart';
import 'package:supanotes/features/tasks/domain/task_projection_engine.dart';
import 'note_editor_controller.dart';
import 'note_editor_session.dart';

typedef NoteEditorSessionRequest = ({String noteId, bool isReadOnly});

final noteEditorSessionProvider = FutureProvider.autoDispose
    .family<NoteEditorSession, NoteEditorSessionRequest>((ref, request) async {
      final noteId = request.noteId;
      final userId = ref.watch(currentUserIdProvider)!;
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
      final taskProjectionEngine = TaskProjectionEngine(database: database);
      final syncService = ref.read(noteOperationsSyncServiceProvider);
      final sessionCoordinator = ref.read(noteSessionCoordinatorProvider);

      ref.onDispose(() {
        unawaited(
          sessionCoordinator.close(noteId).then((_) => controller.dispose()),
        );
      });

      final session = await sessionCoordinator.open(
        noteId,
        () => NoteSyncSessionHandle(
          NoteSyncSession(
            noteId: noteId,
            syncService: syncService,
            document: controller.document,
            editor: controller.editor,
            taskProjectionEngine: taskProjectionEngine,
            userId: userId,
            captureLocalOperations: !request.isReadOnly,
          ),
        ),
      );
      return NoteEditorSession(
        noteId: noteId,
        controller: controller,
        syncSession: session,
      );
    });

final noteEditorControllerProvider = FutureProvider.autoDispose
    .family<NoteEditorController, String>((ref, noteId) async {
      final session = await ref.watch(
        noteEditorSessionProvider((noteId: noteId, isReadOnly: false)).future,
      );
      return session.controller;
    });

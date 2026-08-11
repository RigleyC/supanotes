import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/notes/attachments/data/attachments_repository.dart';
import 'package:supanotes/features/notes/catalog/data/notes_repository.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_session.dart';
import 'package:supanotes/features/tasks/domain/task_projection_engine.dart';
import 'note_editor_controller.dart';
import 'note_editor_session.dart';

final _notePermissionProvider = FutureProvider.autoDispose
    .family<NoteModel?, String>(
      (ref, noteId) => ref.watch(notesRepositoryProvider).getNoteById(noteId),
    );

Future<NoteEditorSession> _openNoteEditorSession(Ref ref, String noteId) async {
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

  final note = await ref.watch(_notePermissionProvider(noteId).future);
  if (isDisposed) {
    throw StateError('Provider disposed before session opening');
  }

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
    final taskProjectionEngine = TaskProjectionEngine(database: database);
    final syncService = ref.read(noteOperationsSyncServiceProvider);

    final syncSession = NoteSyncSession(
      noteId: noteId,
      syncService: syncService,
      document: controller.document,
      editor: controller.editor,
      taskProjectionEngine: taskProjectionEngine,
      userId: userId,
      captureLocalOperations: _canCaptureLocalOperations(note),
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

  permissionSubscription = notesRepository.watchNoteById(noteId).listen((note) {
    session.setCaptureLocalOperations(_canCaptureLocalOperations(note));
  });

  return session;
}

bool _canCaptureLocalOperations(NoteModel? note) {
  return note != null && !note.isReadOnly;
}

/// The sole owner of an editor session for a note.
final noteEditorSessionProvider = FutureProvider.autoDispose
    .family<NoteEditorSession, String>(
      (ref, noteId) => _openNoteEditorSession(ref, noteId),
    );

/// Reactive access capability for the editor chrome and document widgets.
///
/// Permission can change while a session is open, for example after a 403 or
/// a catalog refresh. Consumers must not infer access from a one-time note
/// model read.
final noteEditorCaptureProvider = StreamProvider.autoDispose
    .family<bool, String>((ref, noteId) async* {
      final session = await ref.watch(noteEditorSessionProvider(noteId).future);
      yield session.captureLocalOperations;
      yield* session.captureLocalOperationsChanges;
    });

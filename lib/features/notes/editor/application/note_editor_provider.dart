import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/src/providers/future_provider.dart';
import 'package:riverpod/src/providers/stream_provider.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/notes/attachments/data/attachments_repository.dart';
import 'package:supanotes/features/notes/catalog/data/notes_repository.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_controller.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_session.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_session.dart';

final FutureProviderFamily<NoteModel?, String> _notePermissionProvider = FutureProvider.autoDispose
    .family<NoteModel?, String>(
      (ref, noteId) => ref.watch(notesRepositoryProvider).getNoteById(noteId),
    );

Future<NoteEditorSession> _openNoteEditorSession(Ref ref, String noteId) async {
  final userId = ref.watch(currentUserIdProvider)!;
  final sessionCoordinator = ref.read(noteSessionCoordinatorProvider);
  final notesRepository = ref.watch(notesRepositoryProvider);
  final lifecycleStore = ref.watch(noteLifecycleStoreProvider);

  var isDisposed = false;
  StreamSubscription<NoteModel?>? permissionSubscription;

  Future<void> closeSession() async {
    await sessionCoordinator.close(noteId);
    await lifecycleStore.discardLocalDraft(noteId);
  }

  ref.onDispose(() {
    isDisposed = true;
    unawaited(permissionSubscription?.cancel());
    unawaited(closeSession());
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

    final syncService = ref.read(noteOperationsSyncServiceProvider);

    final syncSession = NoteSyncSession(
      noteId: noteId,
      syncService: syncService,
      document: controller.document,
      editor: controller.editor,
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
    unawaited(closeSession());
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
final FutureProviderFamily<NoteEditorSession, String> noteEditorSessionProvider = FutureProvider.autoDispose
    .family<NoteEditorSession, String>(
      _openNoteEditorSession,
    );

/// Reactive access capability for the editor chrome and document widgets.
///
/// Permission can change while a session is open, for example after a 403 or
/// a catalog refresh. Consumers must not infer access from a one-time note
/// model read.
final StreamProviderFamily<bool, String> noteEditorCaptureProvider = StreamProvider.autoDispose
    .family<bool, String>((ref, noteId) async* {
      final session = await ref.watch(noteEditorSessionProvider(noteId).future);
      yield session.captureLocalOperations;
      yield* session.captureLocalOperationsChanges;
    });

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
import 'package:supanotes/features/notes/sharing/model/share_link_document.dart';
import 'note_editor_controller.dart';
import 'note_editor_session.dart';
import 'note_editor_open_options.dart';

typedef _NoteEditorSessionRequest = ({
  String noteId,
  NoteEditorAccessMode? accessMode,
  String? shareLinkToken,
});

typedef NoteEditorShareLinkSessionRequest = ({String noteId, String token});

Future<Map<String, dynamic>?> _loadShareLinkSnapshot(
  Ref ref,
  String? token,
) async {
  if (token == null) return null;
  final response = await ref
      .read(apiClientProvider)
      .get<Map<String, dynamic>>('/s/${Uri.encodeComponent(token)}/document');
  final document = ShareLinkDocument.fromJson(response.data ?? const {});
  return document.toSnapshot();
}

final _notePermissionProvider = FutureProvider.autoDispose
    .family<NoteModel?, String>(
      (ref, noteId) => ref.watch(notesRepositoryProvider).getNoteById(noteId),
    );

Future<NoteEditorSession> _openNoteEditorSession(
  Ref ref,
  _NoteEditorSessionRequest request,
) async {
  final noteId = request.noteId;
  final sessionKey = request.accessMode == null
      ? noteId
      : '$noteId:${request.accessMode!.name}';
  final userId = ref.watch(currentUserIdProvider)!;
  final sessionCoordinator = ref.read(noteSessionCoordinatorProvider);
  final notesRepository = ref.watch(notesRepositoryProvider);

  bool isDisposed = false;
  StreamSubscription? permissionSubscription;

  ref.onDispose(() {
    isDisposed = true;
    unawaited(permissionSubscription?.cancel());
    unawaited(sessionCoordinator.close(noteId, sessionKey: sessionKey));
  });

  final note = await ref.watch(_notePermissionProvider(noteId).future);
  final initialSnapshot = await _loadShareLinkSnapshot(
    ref,
    request.shareLinkToken,
  );
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
      captureLocalOperations: _canCaptureLocalOperations(
        request.accessMode,
        note,
      ),
      initialSnapshot: initialSnapshot,
    );

    return NoteEditorSession(
      noteId: noteId,
      controller: controller,
      syncSession: syncSession,
    );
  }, sessionKey: sessionKey);

  if (isDisposed) {
    unawaited(sessionCoordinator.close(noteId, sessionKey: sessionKey));
    throw StateError('Provider disposed during session opening');
  }

  permissionSubscription = notesRepository.watchNoteById(noteId).listen((note) {
    session.setCaptureLocalOperations(
      _canCaptureLocalOperations(request.accessMode, note),
    );
  });

  return session;
}

bool _canCaptureLocalOperations(
  NoteEditorAccessMode? accessMode,
  NoteModel? note,
) {
  return switch (accessMode) {
    NoteEditorAccessMode.readOnly => false,
    NoteEditorAccessMode.editable => true,
    null => note != null && !note.isReadOnly,
  };
}

final _noteEditorSessionOwnerProvider = FutureProvider.autoDispose
    .family<NoteEditorSession, _NoteEditorSessionRequest>(
      (ref, request) => _openNoteEditorSession(ref, request),
    );

final noteEditorSessionProvider = FutureProvider.autoDispose
    .family<NoteEditorSession, String>((ref, noteId) async {
      final session = await ref.watch(
        _noteEditorSessionOwnerProvider((
          noteId: noteId,
          accessMode: null,
          shareLinkToken: null,
        )).future,
      );
      return session;
    });

final noteEditorReadOnlySessionProvider = FutureProvider.autoDispose
    .family<NoteEditorSession, String>((ref, noteId) async {
      final session = await ref.watch(
        _noteEditorSessionOwnerProvider((
          noteId: noteId,
          accessMode: NoteEditorAccessMode.readOnly,
          shareLinkToken: null,
        )).future,
      );
      return session;
    });

final noteEditorEditableSessionProvider = FutureProvider.autoDispose
    .family<NoteEditorSession, String>((ref, noteId) async {
      final session = await ref.watch(
        _noteEditorSessionOwnerProvider((
          noteId: noteId,
          accessMode: NoteEditorAccessMode.editable,
          shareLinkToken: null,
        )).future,
      );
      return session;
    });

final noteEditorReadOnlyShareLinkSessionProvider = FutureProvider.autoDispose
    .family<NoteEditorSession, NoteEditorShareLinkSessionRequest>(
      (ref, request) => ref.watch(
        _noteEditorSessionOwnerProvider((
          noteId: request.noteId,
          accessMode: NoteEditorAccessMode.readOnly,
          shareLinkToken: request.token,
        )).future,
      ),
    );

final noteEditorEditableShareLinkSessionProvider = FutureProvider.autoDispose
    .family<NoteEditorSession, NoteEditorShareLinkSessionRequest>(
      (ref, request) => ref.watch(
        _noteEditorSessionOwnerProvider((
          noteId: request.noteId,
          accessMode: NoteEditorAccessMode.editable,
          shareLinkToken: request.token,
        )).future,
      ),
    );

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/notes/data/attachments_repository.dart';
import 'package:supanotes/features/notes/domain/note_sync_session.dart';
import 'note_editor_controller.dart';

final noteEditorControllerProvider = FutureProvider.autoDispose
    .family<NoteEditorController, String>((ref, noteId) async {
  final userId = ref.watch(currentUserIdProvider)!;
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

  controller.initOtOnly(noteId: noteId);

  final syncService = ref.read(noteOperationsSyncServiceProvider);

  final session = NoteSyncSession(
    noteId: noteId,
    syncService: syncService,
    document: controller.document!,
    editor: controller.editor!,
  );

  await session.start();
  controller.operationAdapter = session.adapter;

  ref.onDispose(() {
    session.dispose();
    unawaited(controller.dispose());
  });
  return controller;
});

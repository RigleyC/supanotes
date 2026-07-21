import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/notes/data/attachments_repository.dart';
import 'package:supanotes/features/notes/domain/note_operation_adapter.dart';
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

  var disposed = false;

  final noteOpsSyncService = ref.read(noteOperationsSyncServiceProvider);
  final adapter = NoteOperationAdapter(
    document: controller.document!,
    syncService: noteOpsSyncService,
    noteId: noteId,
    editor: controller.editor!,
  );

  adapter.onLocalOperations = (_) {
    unawaited(noteOpsSyncService.syncPending(noteId).then((result) async {
      if (!disposed && result.canonicalDocument != null) {
        await adapter.reconcile(result);
      }
    }).catchError((error, stackTrace) {
      dev.log(
        'Note operation sync failed',
        error: error,
        stackTrace: stackTrace,
      );
    }));
  };

  await adapter.start();
  if (disposed) {
    controller.dispose();
    throw StateError('Disposed before initialization completed');
  }
  controller.operationAdapter = adapter;

  Timer? pollTimer;
  void startPolling() {
    pollTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (disposed) return;
      try {
        final result = await noteOpsSyncService.pollAndReconcile(noteId);
        if (!disposed && result.canonicalDocument != null) {
          await adapter.reconcile(result);
        }
      } catch (error, stackTrace) {
        dev.log(
          'Note operation poll failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
    });
  }
  startPolling();

  ref.onDispose(() {
    disposed = true;
    pollTimer?.cancel();
    unawaited(controller.dispose());
  });
  return controller;
});

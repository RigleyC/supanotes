import 'dart:async';

import 'package:supanotes/features/notes/domain/note_session_handle.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';

class NoteEditorSession implements NoteEditorSyncHandle {
  NoteEditorSession({
    required this.noteId,
    required this.controller,
    required this.syncSession,
  });

  final String noteId;
  final NoteEditorController controller;
  final NoteEditorSyncHandle syncSession;

  @override
  NoteSessionStatus get status => syncSession.status;

  @override
  Stream<NoteSessionStatus> get statusChanges => syncSession.statusChanges;

  @override
  bool get captureLocalOperations => syncSession.captureLocalOperations;

  @override
  void setCaptureLocalOperations(bool captureLocalOperations) {
    syncSession.setCaptureLocalOperations(captureLocalOperations);
  }

  @override
  Future<void> start() => syncSession.start();

  @override
  Future<void> flushNow() => syncSession.flushNow();

  @override
  Future<void> dispose() async {
    await syncSession.dispose();
    controller.dispose();
  }
}

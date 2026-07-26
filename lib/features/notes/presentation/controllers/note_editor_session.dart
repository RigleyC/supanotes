import 'package:supanotes/features/notes/domain/note_session_coordinator.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';

class NoteEditorSession {
  NoteEditorSession({
    required this.noteId,
    required this.controller,
    CoordinatedNoteSession<NoteSyncSessionHandle>? syncSession,
    NoteSessionStatus status = NoteSessionStatus.ready,
    Future<void> Function()? onFlushNow,
  }) : _syncSession = syncSession,
       _status = status,
       _onFlushNow = onFlushNow;

  final String noteId;
  final NoteEditorController controller;
  final CoordinatedNoteSession<NoteSyncSessionHandle>? _syncSession;
  final NoteSessionStatus _status;
  final Future<void> Function()? _onFlushNow;

  NoteSessionStatus get status => _syncSession?.status ?? _status;

  Future<void> flushNow() {
    final syncSession = _syncSession;
    if (syncSession != null) {
      return syncSession.flushNow();
    }
    return _onFlushNow?.call() ?? Future<void>.value();
  }
}

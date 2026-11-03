import 'dart:async';

enum NoteSessionStatus {
  opening,
  ready,
  syncing,
  syncError,
  blocked,
  closing,
  closed,
  error,
}

abstract interface class NoteSessionHandle {
  NoteSessionStatus get status;
  Stream<NoteSessionStatus> get statusChanges;
  Future<void> start();
  Future<void> flushNow();

  /// Pulls remote changes for the note into the open session. Called by the
  /// app-wide change feed; sessions do not poll on their own. Completes with
  /// `false` when the session cannot take the change (closing or failed), so
  /// the feed applies it to local storage instead.
  Future<bool> reconcileRemote();
  Future<void> dispose();
}

abstract interface class NoteEditorSyncHandle implements NoteSessionHandle {
  bool get captureLocalOperations;
  Stream<bool> get captureLocalOperationsChanges;
  void setCaptureLocalOperations(bool captureLocalOperations);
}

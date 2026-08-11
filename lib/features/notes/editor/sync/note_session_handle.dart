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
  Future<void> dispose();
}

abstract interface class NoteEditorSyncHandle implements NoteSessionHandle {
  bool get captureLocalOperations;
  Stream<bool> get captureLocalOperationsChanges;
  void setCaptureLocalOperations(bool captureLocalOperations);
}

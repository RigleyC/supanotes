import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';

/// The seam between a note's sync session and the editor showing it.
///
/// An adapter captures local edits as REST/OT operations and persists them
/// to the outbox, hydrates the editor from the stored document, and
/// reconciles the editor with server results. The session owns scheduling,
/// network and lifecycle; it never touches the editor directly.
abstract interface class NoteDocumentAdapter {
  /// Called after local operations reach the durable outbox.
  set onLocalOperations(void Function(List<OperationRequest> ops)? callback);

  /// Hydrates the editor from the stored document and pending operations,
  /// then starts capturing local edits (when enabled).
  Future<void> start();

  /// Turns local capture on (editable) or off (read-only).
  void setCaptureLocalOperations(bool captureLocalOperations);

  /// Persists every captured operation and the materialized document now.
  Future<void> flushNow();

  /// Applies a server result (canonical document plus rebased pending
  /// operations) to the editor.
  Future<void> reconcile(SyncResult result);

  void dispose();
}

import 'dart:async';

import 'package:supanotes/core/sync/sync_feed_client.dart';
import 'package:supanotes/core/sync/sync_inbox_store.dart';
import 'package:supanotes/core/sync/sync_inbox_worker.dart';

/// Coordinates one account's remote synchronization lifecycle.
///
/// A new local account snapshot is bootstrapped once from the complete catalog
/// at a stable server watermark. Every later remote mutation is consumed from
/// the durable incremental inbox.
final class NoteRemoteSyncCoordinator {
  NoteRemoteSyncCoordinator({
    required this.userId,
    required SyncInboxStore store,
    required SyncChangesFetcher fetchChanges,
    required Future<void> Function() bootstrapCatalog,
    required bool Function(String noteId) isNoteActive,
    required Future<void> Function(String noteId) syncPending,
    required Future<int?> Function(String noteId) confirmedRevision,
    required Future<void> Function(String noteId) pollAndReconcile,
    required Future<void> Function(String noteId) hydrateRemote,
    required Future<void> Function(String noteId) deleteLocal,
    void Function(SyncInboxEntry change)? onApplied,
  }) : _store = store,
       _fetchChanges = fetchChanges,
       _bootstrapCatalog = bootstrapCatalog,
       _syncPending = syncPending,
       _confirmedRevision = confirmedRevision,
       _pollAndReconcile = pollAndReconcile,
       _hydrateRemote = hydrateRemote,
       _deleteLocal = deleteLocal,
       _onApplied = onApplied {
    _worker = SyncInboxWorker(
      userId: userId,
      store: store,
      fetchChanges: fetchChanges,
      isNoteActive: isNoteActive,
      applyChange: _applyChange,
    );
  }

  final String userId;
  final SyncInboxStore _store;
  final SyncChangesFetcher _fetchChanges;
  final Future<void> Function() _bootstrapCatalog;
  final Future<void> Function(String noteId) _syncPending;
  final Future<int?> Function(String noteId) _confirmedRevision;
  final Future<void> Function(String noteId) _pollAndReconcile;
  final Future<void> Function(String noteId) _hydrateRemote;
  final Future<void> Function(String noteId) _deleteLocal;
  final void Function(SyncInboxEntry change)? _onApplied;

  late final SyncInboxWorker _worker;
  Future<void> _tail = Future<void>.value();
  bool _disposed = false;

  Future<void> syncOnce() {
    if (_disposed) return Future<void>.value();
    final run = _tail.then((_) => _syncOnce());
    _tail = run.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return run;
  }

  Future<void> _syncOnce() async {
    if (!await _store.isBootstrapComplete(userId)) {
      await _bootstrap();
    }
    await _worker.syncOnce();
  }

  Future<void> _bootstrap() async {
    final marker = await _fetchChanges(after: 0, limit: 1);
    final watermark = marker.watermark;
    if (watermark == null) {
      throw StateError('Sync feed bootstrap response is missing a watermark');
    }

    await _bootstrapCatalog();
    await _store.completeBootstrap(userId: userId, cursor: watermark);
  }

  Future<void> _applyChange(SyncInboxEntry change) async {
    final noteId = change.noteId;
    if (noteId == null || noteId.isEmpty) {
      throw StateError(
        'Sync change ${change.sequence} (${change.type}) is missing noteId',
      );
    }

    switch (change.type) {
      case 'note_changed':
        await _applyNoteChanged(change, noteId);
      case 'note_access_changed':
      case 'note_preferences_changed':
        await _syncPending(noteId);
        await _hydrateRemote(noteId);
      case 'note_deleted':
      case 'note_access_revoked':
        await _deleteLocal(noteId);
      default:
        throw StateError('Unsupported sync change type: ${change.type}');
    }
    _onApplied?.call(change);
  }

  Future<void> _applyNoteChanged(
    SyncInboxEntry change,
    String noteId,
  ) async {
    // Local edits are sent first so the following reconciliation cannot
    // replace an effective document while durable local operations still wait
    // to be rebased.
    await _syncPending(noteId);

    final currentRevision = await _confirmedRevision(noteId);
    final remoteRevision = change.revision;
    if (currentRevision != null &&
        (remoteRevision == null || currentRevision < remoteRevision)) {
      await _pollAndReconcile(noteId);
    }

    // The catalog endpoint remains the authoritative source for sharing,
    // preferences and metadata. For a note that does not exist locally yet it
    // also hydrates the full document snapshot.
    await _hydrateRemote(noteId);
  }

  void wake() {
    if (_disposed) return;
    unawaited(syncOnce());
  }

  Future<void> drainInbox() => _worker.drainInbox();

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _tail;
    await _worker.dispose();
  }
}

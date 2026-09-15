import 'dart:async';

import 'package:supanotes/core/sync/sync_feed_client.dart';
import 'package:supanotes/core/sync/sync_inbox_store.dart';
import 'package:supanotes/core/sync/sync_inbox_worker.dart';

/// A remote bootstrap fetched before the local checkpoint transaction starts.
///
/// The callbacks must only apply already-materialized data to the open local
/// transaction. Network fetches belong in [NoteRemoteSyncBootstrapFetcher],
/// before [SyncInboxStore.completeBootstrap] opens that transaction.
final class NoteRemoteSyncBootstrap {
  const NoteRemoteSyncBootstrap({
    required this.applyNotesInTransaction,
    this.applyTasksInTransaction,
  });

  final Future<void> Function() applyNotesInTransaction;
  final Future<void> Function()? applyTasksInTransaction;
}

typedef NoteRemoteSyncBootstrapFetcher =
    Future<NoteRemoteSyncBootstrap> Function();

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
    required NoteRemoteSyncBootstrapFetcher fetchBootstrap,
    required bool Function(String noteId) isNoteActive,
    required Future<void> Function(String noteId) syncPending,
    required Future<int?> Function(String noteId) confirmedRevision,
    required Future<void> Function(String noteId) pollAndReconcile,
    required Future<void> Function(String noteId) hydrateRemote,
    required Future<void> Function(String noteId) deleteLocal,
    bool bootstrapTasksAvailable = false,
    Future<void> Function(String taskId)? applyTaskChanged,
    Future<void> Function(String taskId)? applyTaskDeleted,
    void Function(SyncInboxEntry change)? onApplied,
  }) : _store = store,
       _fetchChanges = fetchChanges,
       _fetchBootstrap = fetchBootstrap,
       _syncPending = syncPending,
       _confirmedRevision = confirmedRevision,
       _pollAndReconcile = pollAndReconcile,
       _hydrateRemote = hydrateRemote,
       _deleteLocal = deleteLocal,
       _bootstrapTasksAvailable = bootstrapTasksAvailable,
       _applyTaskChanged = applyTaskChanged,
       _applyTaskDeleted = applyTaskDeleted,
       _onApplied = onApplied {
    _worker = SyncInboxWorker(
      userId: userId,
      store: store,
      fetchChanges: fetchChanges,
      isNoteActive: isNoteActive,
      applyChange: _applyChange,
      scope: SyncFeedScope.notes,
    );
  }

  final String userId;
  final SyncInboxStore _store;
  final SyncChangesFetcher _fetchChanges;
  final NoteRemoteSyncBootstrapFetcher _fetchBootstrap;
  final Future<void> Function(String noteId) _syncPending;
  final Future<int?> Function(String noteId) _confirmedRevision;
  final Future<void> Function(String noteId) _pollAndReconcile;
  final Future<void> Function(String noteId) _hydrateRemote;
  final Future<void> Function(String noteId) _deleteLocal;
  final bool _bootstrapTasksAvailable;
  final Future<void> Function(String taskId)? _applyTaskChanged;
  final Future<void> Function(String taskId)? _applyTaskDeleted;
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
    final bootstrapVersion = await _store.getBootstrapVersion(userId);
    if (bootstrapVersion < 2 && _bootstrapTasksAvailable) {
      await _bootstrap();
    } else if (!await _store.isBootstrapComplete(userId)) {
      await _bootstrap();
    }
    _worker.scope = (await _store.getBootstrapVersion(userId)) >= 2
        ? SyncFeedScope.all
        : SyncFeedScope.notes;
    await _worker.syncOnce();
  }

  Future<void> _bootstrap() async {
    // Notes scope is enough to establish the initial cursor while the task
    // snapshot is being fetched. Any task event before this cursor is already
    // represented by that snapshot; later task events are read once scope=all
    // is enabled.
    final marker = await _fetchChanges(
      after: 0,
      limit: 1,
      scope: SyncFeedScope.notes,
    );
    final watermark = marker.watermark;
    if (watermark == null) {
      throw StateError('Sync feed bootstrap response is missing a watermark');
    }

    // Fetch and materialize remote snapshots before opening the local
    // transaction. The returned callbacks only write those snapshots locally.
    final snapshot = await _fetchBootstrap();
    if (_bootstrapTasksAvailable && snapshot.applyTasksInTransaction == null) {
      throw StateError(
        'Task bootstrap is enabled but the remote snapshot has no task apply callback',
      );
    }
    await _store.completeBootstrap(
      userId: userId,
      cursor: watermark,
      bootstrapVersion: _bootstrapTasksAvailable ? 2 : 0,
      applySnapshotInTransaction: () async {
        await snapshot.applyNotesInTransaction();
        await snapshot.applyTasksInTransaction?.call();
      },
    );
  }

  Future<void> _applyChange(SyncInboxEntry change) async {
    if (change.type == 'task_changed' || change.type == 'task_deleted') {
      final taskId = change.taskId;
      if (taskId == null || taskId.isEmpty) {
        throw StateError(
          'Sync change ${change.sequence} (${change.type}) is missing taskId',
        );
      }
      if (change.type == 'task_changed') {
        final applyTaskChanged = _applyTaskChanged;
        if (applyTaskChanged == null) {
          throw StateError('No handler registered for task_changed');
        }
        await applyTaskChanged(taskId);
      } else {
        final applyTaskDeleted = _applyTaskDeleted;
        if (applyTaskDeleted == null) {
          throw StateError('No handler registered for task_deleted');
        }
        await applyTaskDeleted(taskId);
      }
      _onApplied?.call(change);
      return;
    }

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

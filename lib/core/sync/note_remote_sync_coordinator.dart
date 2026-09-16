import 'dart:async';

import 'package:supanotes/core/sync/sync_feed_client.dart';
import 'package:supanotes/core/sync/sync_inbox_store.dart';
import 'package:supanotes/core/sync/sync_inbox_worker.dart';

/// Applies note feed changes. The coordinator only owns the account feed
/// checkpoint; note ordering and reconciliation stay in the note service.
final class NoteRemoteSyncNoteApplier {
  const NoteRemoteSyncNoteApplier({
    required this.isActive,
    required this.syncPending,
    required this.confirmedRevision,
    required this.pollAndReconcile,
    required this.hydrateRemote,
    required this.deleteLocal,
  });

  final bool Function(String noteId) isActive;
  final Future<void> Function(String noteId) syncPending;
  final Future<int?> Function(String noteId) confirmedRevision;
  final Future<void> Function(String noteId) pollAndReconcile;
  final Future<void> Function(String noteId) hydrateRemote;
  final Future<void> Function(String noteId) deleteLocal;

  Future<void> apply(SyncInboxEntry change) async {
    final noteId = change.noteId;
    if (noteId == null || noteId.isEmpty) {
      throw StateError(
        'Sync change ${change.sequence} (${change.type}) is missing noteId',
      );
    }

    switch (change.type) {
      case 'note_changed':
        await syncPending(noteId);
        final currentRevision = await confirmedRevision(noteId);
        final remoteRevision = change.revision;
        if (currentRevision != null &&
            (remoteRevision == null || currentRevision < remoteRevision)) {
          await pollAndReconcile(noteId);
        }
        await hydrateRemote(noteId);
      case 'note_access_changed':
      case 'note_preferences_changed':
        await syncPending(noteId);
        await hydrateRemote(noteId);
      case 'note_deleted':
      case 'note_access_revoked':
        await deleteLocal(noteId);
      default:
        throw StateError('Unsupported sync change type: ${change.type}');
    }
  }
}

/// Task feed adapter. Disabled sync is explicit instead of optional callbacks
/// on the coordinator.
abstract interface class NoteRemoteSyncTaskApplier {
  bool get enabled;

  Future<void> applyChanged(String taskId);
  Future<void> applyDeleted(String taskId);
}

final class DisabledNoteRemoteSyncTaskApplier
    implements NoteRemoteSyncTaskApplier {
  const DisabledNoteRemoteSyncTaskApplier();

  @override
  bool get enabled => false;

  @override
  Future<void> applyChanged(String taskId) => _unsupported(taskId, 'changed');

  @override
  Future<void> applyDeleted(String taskId) => _unsupported(taskId, 'deleted');

  Future<void> _unsupported(String taskId, String action) {
    return Future.error(
      StateError('Task $action handler is unavailable for $taskId'),
    );
  }
}

final class NoteRemoteSyncTaskCallbacks implements NoteRemoteSyncTaskApplier {
  const NoteRemoteSyncTaskCallbacks({
    required Future<void> Function(String taskId) applyChanged,
    required Future<void> Function(String taskId) applyDeleted,
  }) : _applyChanged = applyChanged,
       _applyDeleted = applyDeleted;

  @override
  Future<void> applyChanged(String taskId) => _applyChanged(taskId);

  @override
  Future<void> applyDeleted(String taskId) => _applyDeleted(taskId);

  final Future<void> Function(String taskId) _applyChanged;
  final Future<void> Function(String taskId) _applyDeleted;

  @override
  bool get enabled => true;
}

final class NoteRemoteSyncBootstrap {
  const NoteRemoteSyncBootstrap({
    required this.applyNotesInTransaction,
    required this.applyTasksInTransaction,
  });

  final Future<void> Function() applyNotesInTransaction;
  final Future<void> Function() applyTasksInTransaction;
}

typedef NoteRemoteSyncBootstrapFetcher =
    Future<NoteRemoteSyncBootstrap> Function();

/// Coordinates one account's feed checkpoint and delegates resource policy to
/// typed note/task appliers.
final class NoteRemoteSyncCoordinator {
  NoteRemoteSyncCoordinator({
    required this.userId,
    required SyncInboxStore store,
    required SyncChangesFetcher fetchChanges,
    required NoteRemoteSyncBootstrapFetcher fetchBootstrap,
    required NoteRemoteSyncNoteApplier noteApplier,
    required NoteRemoteSyncTaskApplier taskApplier,
  }) : _store = store,
       _fetchChanges = fetchChanges,
       _fetchBootstrap = fetchBootstrap,
       _taskApplier = taskApplier {
    _worker = SyncInboxWorker(
      userId: userId,
      store: store,
      fetchChanges: fetchChanges,
      isNoteActive: noteApplier.isActive,
      applyChange: (change) => _applyChange(change, noteApplier),
      scope: taskApplier.enabled ? SyncFeedScope.all : SyncFeedScope.notes,
    );
  }

  final String userId;
  final SyncInboxStore _store;
  final SyncChangesFetcher _fetchChanges;
  final NoteRemoteSyncBootstrapFetcher _fetchBootstrap;
  final NoteRemoteSyncTaskApplier _taskApplier;

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
    if (_taskApplier.enabled && bootstrapVersion < 2) {
      await _bootstrap();
    } else if (!await _store.isBootstrapComplete(userId)) {
      await _bootstrap();
    }
    _worker.scope = _taskApplier.enabled
        ? SyncFeedScope.all
        : SyncFeedScope.notes;
    await _worker.syncOnce();
  }

  Future<void> _bootstrap() async {
    final marker = await _fetchChanges(
      after: 0,
      limit: 1,
      scope: _taskApplier.enabled ? SyncFeedScope.all : SyncFeedScope.notes,
    );
    final watermark = marker.watermark;
    if (watermark == null) {
      throw StateError('Sync feed bootstrap response is missing a watermark');
    }

    final snapshot = await _fetchBootstrap();
    await _store.completeBootstrap(
      userId: userId,
      cursor: watermark,
      bootstrapVersion: _taskApplier.enabled ? 2 : 0,
      applySnapshotInTransaction: () async {
        await snapshot.applyNotesInTransaction();
        await snapshot.applyTasksInTransaction();
      },
    );
  }

  Future<void> _applyChange(
    SyncInboxEntry change,
    NoteRemoteSyncNoteApplier noteApplier,
  ) async {
    if (change.type == 'task_changed' || change.type == 'task_deleted') {
      final taskId = change.taskId;
      if (taskId == null || taskId.isEmpty) {
        throw StateError(
          'Sync change ${change.sequence} (${change.type}) is missing taskId',
        );
      }
      if (!_taskApplier.enabled) {
        throw StateError('Task change received while task sync is disabled');
      }
      if (change.type == 'task_changed') {
        await _taskApplier.applyChanged(taskId);
      } else {
        await _taskApplier.applyDeleted(taskId);
      }
      return;
    }
    await noteApplier.apply(change);
  }

  void wake() {
    if (_disposed) return;
    unawaited(syncOnce());
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _tail;
    await _worker.dispose();
  }
}

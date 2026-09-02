import 'dart:async';

import 'package:supanotes/core/sync/sync_feed_client.dart';
import 'package:supanotes/core/sync/sync_inbox_store.dart';

final class SyncInboxWorker {
  SyncInboxWorker({
    required this.userId,
    required SyncInboxStore store,
    required SyncChangesFetcher fetchChanges,
    required bool Function(String noteId) isNoteActive,
    required Future<void> Function(SyncInboxEntry change) applyChange,
    this.pageSize = 100,
  }) : _store = store,
       _fetchChanges = fetchChanges,
       _isNoteActive = isNoteActive,
       _applyChange = applyChange;

  final String userId;
  final SyncInboxStore _store;
  final SyncChangesFetcher _fetchChanges;
  final bool Function(String noteId) _isNoteActive;
  final Future<void> Function(SyncInboxEntry change) _applyChange;
  final int pageSize;

  Future<void> _tail = Future<void>.value();
  bool _disposed = false;

  Future<void> syncOnce() {
    if (_disposed) return Future<void>.value();
    final run = _tail.then((_) => _syncOnce());
    _tail = run.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return run;
  }

  Future<void> _syncOnce() async {
    await drainInbox();

    while (!_disposed) {
      final before = await _store.getCursor(userId);
      final page = await _fetchChanges(after: before, limit: pageSize);
      if (page.cursor < before) {
        throw StateError(
          'Sync feed cursor moved backwards (${page.cursor} < $before)',
        );
      }
      if (page.hasMore && page.cursor <= before) {
        throw StateError('Sync feed did not advance while hasMore=true');
      }

      await _store.ingestPage(userId: userId, page: page);
      await drainInbox();
      if (!page.hasMore) return;
    }
  }

  Future<void> drainInbox() async {
    if (_disposed) return;
    final pending = await _store.listPending(userId);
    for (final change in pending) {
      if (_disposed) return;
      final noteId = change.noteId;
      if (noteId != null && noteId.isNotEmpty && _isNoteActive(noteId)) {
        continue;
      }
      await _applyChange(change);
      await _store.markApplied(userId: userId, sequence: change.sequence);
    }
  }

  void wake() {
    if (_disposed) return;
    unawaited(syncOnce());
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _tail;
  }
}

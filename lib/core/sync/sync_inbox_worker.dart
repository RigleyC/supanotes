import 'dart:async';

import 'package:supanotes/core/sync/sync_feed_client.dart';
import 'package:supanotes/core/sync/sync_inbox_store.dart';

final class SyncInboxWorker {
  SyncInboxWorker({
    required this.userId,
    required SyncInboxStore store,
    required SyncChangesFetcher fetchChanges,
    required bool Function(SyncInboxEntry change) deferChange,
    required Future<void> Function(SyncInboxEntry change) applyChange,
    this.pageSize = 100,
    this.scope = SyncFeedScope.notes,
  }) : _store = store,
       _fetchChanges = fetchChanges,
       _deferChange = deferChange,
       _applyChange = applyChange;

  final String userId;
  final SyncInboxStore _store;
  final SyncChangesFetcher _fetchChanges;

  /// Changes that must stay in the inbox for now (e.g. deleting a note that
  /// is open in the editor); they are retried on the next pass.
  final bool Function(SyncInboxEntry change) _deferChange;
  final Future<void> Function(SyncInboxEntry change) _applyChange;
  final int pageSize;
  SyncFeedScope scope;

  Future<void> _tail = Future<void>.value();
  bool _disposed = false;

  /// Fetches and applies feed changes; completes with the number of changes
  /// applied, which lets the caller pace the next run.
  Future<int> syncOnce() {
    if (_disposed) return Future<int>.value(0);
    final run = _tail.then((_) => _syncOnce());
    _tail = run.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return run;
  }

  Future<int> _syncOnce() async {
    var applied = await drainInbox();

    while (!_disposed) {
      final before = await _store.getCursor(userId);
      final page = await _fetchChanges(
        after: before,
        limit: pageSize,
        scope: scope,
      );
      if (page.cursor < before) {
        throw StateError(
          'Sync feed cursor moved backwards (${page.cursor} < $before)',
        );
      }
      if (page.hasMore && page.cursor <= before) {
        throw StateError('Sync feed did not advance while hasMore=true');
      }

      await _store.ingestPage(userId: userId, page: page);
      applied += await drainInbox();
      if (!page.hasMore) return applied;
    }
    return applied;
  }

  /// Applies pending inbox changes and returns how many were applied.
  Future<int> drainInbox() async {
    if (_disposed) return 0;
    final pending = await _store.listPending(userId);
    var applied = 0;
    for (final change in pending) {
      if (_disposed) return applied;
      if (_deferChange(change)) continue;
      await _applyChange(change);
      await _store.markApplied(userId: userId, sequence: change.sequence);
      applied++;
    }
    return applied;
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

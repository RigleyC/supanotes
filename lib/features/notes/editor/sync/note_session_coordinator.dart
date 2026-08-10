import 'dart:async';

import 'package:supanotes/core/debug/note_sync_debug.dart';
import 'package:supanotes/features/notes/editor/sync/note_session_activity_tracker.dart';
import 'package:supanotes/features/notes/editor/sync/note_session_handle.dart';

export 'package:supanotes/features/notes/editor/sync/note_session_handle.dart';

class NoteSessionSnapshot {
  const NoteSessionSnapshot({
    required this.activeCount,
    required this.sessionsByStatus,
  });

  final int activeCount;
  final Map<NoteSessionStatus, int> sessionsByStatus;
}

class NoteSessionCoordinator<T extends NoteSessionHandle> {
  NoteSessionCoordinator({NoteSessionActivityTracker? activityTracker})
    : _activityTracker = activityTracker;

  final NoteSessionActivityTracker? _activityTracker;
  final Map<String, _SessionEntry<T>> _entries = {};
  bool _disposed = false;

  NoteSessionStatus _entryStatus(_SessionEntry<T>? entry) {
    if (entry == null) return NoteSessionStatus.closed;
    if (entry.session == null) {
      return entry.isClosing
          ? NoteSessionStatus.closing
          : NoteSessionStatus.opening;
    }
    return entry.session!.status;
  }

  NoteSessionStatus statusOf(String noteId, {String? sessionKey}) {
    return _entryStatus(_entries[sessionKey ?? noteId]);
  }

  Stream<NoteSessionStatus> statusChangesOf(
    String noteId, {
    String? sessionKey,
  }) {
    final entry = _entries[sessionKey ?? noteId];
    if (entry == null || entry.session == null) {
      return Stream<NoteSessionStatus>.value(_entryStatus(entry));
    }
    return entry.session!.statusChanges;
  }

  NoteSessionSnapshot snapshot() {
    final counts = <NoteSessionStatus, int>{
      for (final status in NoteSessionStatus.values) status: 0,
    };
    for (final entry in _entries.values) {
      final status = _entryStatus(entry);
      counts[status] = counts[status]! + 1;
    }
    return NoteSessionSnapshot(
      activeCount: _activityTracker?.activeCount ?? _entries.length,
      sessionsByStatus: Map.unmodifiable(counts),
    );
  }

  Future<T> open(
    String noteId,
    FutureOr<T> Function() create, {
    String? sessionKey,
  }) async {
    _assertCoordinatorOpen();
    final key = sessionKey ?? noteId;

    while (true) {
      final current = _entries[key];
      if (current == null) {
        break;
      }
      if (current.isClosing) {
        await current.closeFuture;
      } else {
        return current.openFuture;
      }
    }

    final entry = _SessionEntry<T>(noteId: noteId, key: key);
    _entries[key] = entry;
    _activityTracker?.markActive(noteId, sessionKey: key);

    NoteSyncDebug.log(
      'session.open',
      noteId: noteId,
      fields: {'activeCount': snapshot().activeCount},
    );

    final openCompleter = Completer<T>();
    entry.openFuture = openCompleter.future;

    () async {
      try {
        final session = await create();
        entry.session = session;
        if (entry.isClosing) {
          await entry.disposeSessionOnce();
          throw StateError('Session opening was cancelled by close()');
        }
        await session.start();
        if (entry.isClosing) {
          await entry.disposeSessionOnce();
          throw StateError('Session opening was cancelled by close()');
        }
        openCompleter.complete(session);
      } catch (error, stack) {
        await entry.disposeSessionOnce();
        if (_entries[key] == entry) {
          _entries.remove(key);
          _activityTracker?.markInactive(noteId, sessionKey: key);
        }
        NoteSyncDebug.log(
          'session.open.error',
          noteId: noteId,
          fields: {'errorClass': NoteSyncDebug.errorClass(error)},
        );
        openCompleter.completeError(error, stack);
      }
    }();

    return openCompleter.future;
  }

  Future<void> close(String noteId, {String? sessionKey}) async {
    final key = sessionKey ?? noteId;
    final entry = _entries[key];
    if (entry == null) return;
    if (entry.isClosing) {
      return entry.closeFuture;
    }

    entry.isClosing = true;
    entry.closeFuture = () async {
      try {
        try {
          await entry.openFuture;
        } catch (_) {
          // Open future failures handle disposal in their catch block
        }
        await entry.disposeSessionOnce();
      } finally {
        if (_entries[key] == entry) {
          _entries.remove(key);
          _activityTracker?.markInactive(noteId, sessionKey: entry.key);
        }
      }
    }();

    await entry.closeFuture;
  }

  Future<void> closeAll() async {
    if (_disposed) return;
    _disposed = true;
    final entries = List<_SessionEntry<T>>.from(_entries.values);
    await Future.wait(
      entries.map((entry) => close(entry.noteId, sessionKey: entry.key)),
    );
  }

  void _assertCoordinatorOpen() {
    if (_disposed) {
      throw StateError('Note session coordinator is closed');
    }
  }
}

class _SessionEntry<T extends NoteSessionHandle> {
  _SessionEntry({required this.noteId, required this.key});

  final String noteId;
  final String key;
  T? session;
  late Future<T> openFuture;
  Future<void>? closeFuture;
  bool isClosing = false;
  bool _disposed = false;

  Future<void> disposeSessionOnce() async {
    if (_disposed || session == null) return;
    _disposed = true;
    await session!.dispose();
  }
}

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

  NoteSessionStatus statusOf(String noteId) {
    return _entryStatus(_entries[noteId]);
  }

  Stream<NoteSessionStatus> statusChangesOf(String noteId) {
    final entry = _entries[noteId];
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

  Future<T> open(String noteId, FutureOr<T> Function() create) {
    _assertCoordinatorOpen();
    final current = _entries[noteId];
    if (current == null) return _startOpening(noteId, create);
    if (!current.isClosing) return current.openFuture;
    return _openAfterClosing(noteId, create);
  }

  Future<T> _startOpening(String noteId, FutureOr<T> Function() create) {
    final entry = _registerOpeningEntry(noteId);
    final openCompleter = Completer<T>();
    entry.openFuture = openCompleter.future;
    unawaited(_openEntry(entry, create, openCompleter));
    return openCompleter.future;
  }

  Future<T> _openAfterClosing(
    String noteId,
    FutureOr<T> Function() create,
  ) async {
    while (true) {
      final current = _entries[noteId];
      if (current == null) {
        return _startOpening(noteId, create);
      }
      if (current.isClosing) {
        await current.closeFuture;
      } else {
        return current.openFuture;
      }
    }
  }

  _SessionEntry<T> _registerOpeningEntry(String noteId) {
    final entry = _SessionEntry<T>(noteId: noteId);
    _entries[noteId] = entry;
    _activityTracker?.markActive(noteId);

    NoteSyncDebug.log(
      'session.open',
      noteId: noteId,
      fields: {'activeCount': snapshot().activeCount},
    );
    return entry;
  }

  Future<void> _openEntry(
    _SessionEntry<T> entry,
    FutureOr<T> Function() create,
    Completer<T> openCompleter,
  ) async {
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
      await _completeFailedOpen(entry, openCompleter, error, stack);
    }
  }

  Future<void> _completeFailedOpen(
    _SessionEntry<T> entry,
    Completer<T> openCompleter,
    Object error,
    StackTrace stack,
  ) async {
    Object reportedError = error;
    StackTrace reportedStack = stack;
    try {
      await entry.disposeSessionOnce();
    } catch (disposeError, disposeStack) {
      reportedError = disposeError;
      reportedStack = disposeStack;
      NoteSyncDebug.log(
        'session.open.dispose_error',
        noteId: entry.noteId,
        fields: {'errorClass': NoteSyncDebug.errorClass(disposeError)},
      );
    }
    if (_entries[entry.noteId] == entry && entry.isDisposed) {
      _entries.remove(entry.noteId);
      _activityTracker?.markInactive(entry.noteId);
    }
    NoteSyncDebug.log(
      'session.open.error',
      noteId: entry.noteId,
      fields: {'errorClass': NoteSyncDebug.errorClass(reportedError)},
    );
    openCompleter.completeError(reportedError, reportedStack);
  }

  Future<void> close(String noteId) async {
    final entry = _entries[noteId];
    if (entry == null) return;
    if (entry.isClosing) {
      return entry.closeFuture;
    }

    entry.isClosing = true;
    final closeFuture = () async {
      try {
        try {
          await entry.openFuture;
        } catch (_) {
          // Open future failures handle disposal in their catch block
        }
        await entry.disposeSessionOnce();
      } catch (_) {
        // A failed close leaves the session and its durable-retry state in
        // place. The next close call must be able to retry it.
        entry.isClosing = false;
        entry.closeFuture = null;
        rethrow;
      }
      if (_entries[noteId] == entry) {
        _entries.remove(noteId);
        _activityTracker?.markInactive(noteId);
      }
    }();
    entry.closeFuture = closeFuture;

    await closeFuture;
  }

  Future<void> closeAll() async {
    if (_disposed) return;
    _disposed = true;
    final entries = List<_SessionEntry<T>>.from(_entries.values);
    try {
      await Future.wait(entries.map((entry) => close(entry.noteId)));
    } catch (_) {
      _disposed = false;
      rethrow;
    }
  }

  void _assertCoordinatorOpen() {
    if (_disposed) {
      throw StateError('Note session coordinator is closed');
    }
  }
}

class _SessionEntry<T extends NoteSessionHandle> {
  _SessionEntry({required this.noteId});

  final String noteId;
  T? session;
  late Future<T> openFuture;
  Future<void>? closeFuture;
  bool isClosing = false;
  bool _disposed = false;
  bool get isDisposed => _disposed;

  Future<void> disposeSessionOnce() async {
    if (_disposed) return;
    final current = session;
    if (current == null) {
      _disposed = true;
      return;
    }
    await current.dispose();
    _disposed = true;
  }
}

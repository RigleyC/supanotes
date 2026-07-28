import 'dart:async';

import 'package:supanotes/core/debug/note_sync_debug.dart';
import 'package:supanotes/features/notes/domain/note_session_activity_tracker.dart';
import 'package:supanotes/features/notes/domain/note_session_handle.dart';

export 'package:supanotes/features/notes/domain/note_session_handle.dart';

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

  Future<T> open(
    String noteId,
    FutureOr<T> Function() create,
  ) async {
    _assertCoordinatorOpen();

    while (true) {
      final current = _entries[noteId];
      if (current == null) {
        break;
      }
      if (current.isClosing) {
        await current.closeFuture;
      } else {
        return current.openFuture;
      }
    }

    final entry = _SessionEntry<T>(noteId: noteId);
    _entries[noteId] = entry;
    _activityTracker?.markActive(noteId);

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
        if (_entries[noteId] == entry) {
          _entries.remove(noteId);
          _activityTracker?.markInactive(noteId);
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

  Future<void> close(String noteId) async {
    final entry = _entries[noteId];
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
        if (_entries[noteId] == entry) {
          _entries.remove(noteId);
          _activityTracker?.markInactive(noteId);
        }
      }
    }();

    await entry.closeFuture;
  }

  Future<void> closeAll() async {
    if (_disposed) return;
    _disposed = true;
    final entries = List<_SessionEntry<T>>.from(_entries.values);
    await Future.wait(entries.map((entry) => close(entry.noteId)));
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

  Future<void> disposeSessionOnce() async {
    if (_disposed || session == null) return;
    _disposed = true;
    await session!.dispose();
  }
}

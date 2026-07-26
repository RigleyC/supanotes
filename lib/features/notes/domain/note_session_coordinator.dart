import 'dart:async';

import 'package:supanotes/features/notes/domain/note_session_activity_tracker.dart';
import 'package:supanotes/features/notes/domain/note_sync_session.dart';

enum NoteSessionStatus { opening, ready, syncing, closing, closed, error }

abstract interface class NoteSessionHandle {
  Future<void> start();
  Future<void> flushNow();
  Future<void> dispose();
}

class NoteSyncSessionHandle implements NoteSessionHandle {
  NoteSyncSessionHandle(this.session);

  final NoteSyncSession session;

  @override
  Future<void> start() => session.start();

  @override
  Future<void> flushNow() => session.flushNow();

  @override
  Future<void> dispose() => session.dispose();
}

typedef NoteSessionFactory<T extends NoteSessionHandle> = T Function();

class CoordinatedNoteSession<T extends NoteSessionHandle> {
  CoordinatedNoteSession._({
    required this.noteId,
    required int generation,
    required T handle,
    required NoteSessionCoordinator<T> coordinator,
  }) : _generation = generation,
       _handle = handle,
       _coordinator = coordinator;

  final String noteId;
  final int _generation;
  final T _handle;
  final NoteSessionCoordinator<T> _coordinator;

  NoteSessionStatus get status => _coordinator._statusOf(noteId, _generation);

  T get handle {
    _coordinator._assertCanUse(noteId, _generation);
    return _handle;
  }

  Future<void> flushNow() {
    _coordinator._assertCanUse(noteId, _generation);
    _coordinator._setStatus(noteId, _generation, NoteSessionStatus.syncing);
    return _handle.flushNow().whenComplete(() {
      _coordinator._setReadyIfStillSyncing(noteId, _generation);
    });
  }
}

class NoteSessionCoordinator<T extends NoteSessionHandle> {
  NoteSessionCoordinator({NoteSessionActivityTracker? activityTracker})
    : _activityTracker = activityTracker;

  final NoteSessionActivityTracker? _activityTracker;
  final Map<String, _SessionEntry<T>> _entries = {};
  int _nextGeneration = 0;
  bool _disposed = false;

  NoteSessionStatus statusOf(String noteId) {
    return _entries[noteId]?.status ?? NoteSessionStatus.closed;
  }

  Future<CoordinatedNoteSession<T>> open(
    String noteId,
    NoteSessionFactory<T> create,
  ) async {
    _assertCoordinatorOpen();

    final current = _entries[noteId];
    if (current != null) {
      switch (current.status) {
        case NoteSessionStatus.opening:
        case NoteSessionStatus.ready:
        case NoteSessionStatus.syncing:
          return current.openFuture;
        case NoteSessionStatus.closing:
          await current.close();
        case NoteSessionStatus.closed:
        case NoteSessionStatus.error:
          break;
      }
    }

    final generation = ++_nextGeneration;
    final handle = create();
    _activityTracker?.markActive(noteId);
    late final _SessionEntry<T> entry;
    entry = _SessionEntry<T>(
      noteId: noteId,
      generation: generation,
      handle: handle,
      coordinator: this,
      start: () => _start(noteId, generation, handle),
    );
    _entries[noteId] = entry;
    return entry.openFuture;
  }

  Future<void> close(String noteId) async {
    final entry = _entries[noteId];
    if (entry == null) return;
    await entry.close();
  }

  Future<void> closeAll() async {
    _disposed = true;
    final entries = List<_SessionEntry<T>>.from(_entries.values);
    await Future.wait(entries.map((entry) => entry.close()));
  }

  Future<CoordinatedNoteSession<T>> _start(
    String noteId,
    int generation,
    T handle,
  ) async {
    try {
      await handle.start();
      _setStatus(noteId, generation, NoteSessionStatus.ready);
      return CoordinatedNoteSession._(
        noteId: noteId,
        generation: generation,
        handle: handle,
        coordinator: this,
      );
    } catch (error) {
      _setStatus(noteId, generation, NoteSessionStatus.error);
      await handle.dispose();
      rethrow;
    }
  }

  NoteSessionStatus _statusOf(String noteId, int generation) {
    final entry = _entries[noteId];
    if (entry == null || entry.generation != generation) {
      return NoteSessionStatus.closed;
    }
    return entry.status;
  }

  void _setStatus(String noteId, int generation, NoteSessionStatus status) {
    final entry = _entries[noteId];
    if (entry == null || entry.generation != generation) return;
    entry.status = status;
    if (status == NoteSessionStatus.closed && entry.generation == generation) {
      _entries.remove(noteId);
      _activityTracker?.markInactive(noteId);
    }
  }

  void _setReadyIfStillSyncing(String noteId, int generation) {
    final entry = _entries[noteId];
    if (entry == null ||
        entry.generation != generation ||
        entry.status != NoteSessionStatus.syncing) {
      return;
    }
    entry.status = NoteSessionStatus.ready;
  }

  void _assertCanUse(String noteId, int generation) {
    _assertCoordinatorOpen();
    final entry = _entries[noteId];
    if (entry == null || entry.generation != generation) {
      throw StateError('Note session is no longer active');
    }
    if (entry.status == NoteSessionStatus.closing ||
        entry.status == NoteSessionStatus.closed ||
        entry.status == NoteSessionStatus.error) {
      throw StateError('Note session is not accepting mutations');
    }
  }

  void _assertCoordinatorOpen() {
    if (_disposed) {
      throw StateError('Note session coordinator is closed');
    }
  }
}

class _SessionEntry<T extends NoteSessionHandle> {
  _SessionEntry({
    required this.noteId,
    required this.generation,
    required this.handle,
    required this.coordinator,
    required Future<CoordinatedNoteSession<T>> Function() start,
  }) : openFuture = start();

  final String noteId;
  final int generation;
  final T handle;
  final NoteSessionCoordinator<T> coordinator;
  final Future<CoordinatedNoteSession<T>> openFuture;

  NoteSessionStatus status = NoteSessionStatus.opening;
  Future<void>? _closeFuture;

  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;

    final future = _close();
    _closeFuture = future;
    return future;
  }

  Future<void> _close() async {
    if (status == NoteSessionStatus.closed) return;
    if (status == NoteSessionStatus.error) {
      coordinator._setStatus(noteId, generation, NoteSessionStatus.closed);
      return;
    }
    coordinator._setStatus(noteId, generation, NoteSessionStatus.closing);
    try {
      try {
        await openFuture;
      } catch (_) {
        // Opening failure already moved this entry to error and rolled back
        // created resources. Close still completes idempotently.
      }
      await handle.dispose();
    } finally {
      coordinator._setStatus(noteId, generation, NoteSessionStatus.closed);
    }
  }
}

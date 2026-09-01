import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';

typedef PendingNoteIdsLoader = Future<List<String>> Function();
typedef NoteSyncRunner = Future<SyncResult> Function(String noteId);
typedef NoteActivePredicate = bool Function(String noteId);
typedef SyncClock = DateTime Function();
typedef SyncBackoff = Duration Function(int attempt);
typedef SyncProtocolErrorPredicate = bool Function(Object error);

class _RetryState {
  const _RetryState({required this.attempt, required this.nextAttemptAt});

  final int attempt;
  final DateTime nextAttemptAt;
}

/// Drains durable REST/OT note operations independently from an open editor.
///
/// Open notes are intentionally skipped because their [NoteSyncSession] owns
/// reconciliation with the visible document. This worker exists for durable
/// outbox rows that remain after a note session closes, an app restart, or a
/// transient network failure.
class NoteOutboxWorker {
  NoteOutboxWorker({
    required PendingNoteIdsLoader loadPendingNoteIds,
    required NoteSyncRunner syncNote,
    required NoteActivePredicate isNoteActive,
    SyncClock? now,
    SyncBackoff? backoffForAttempt,
    SyncProtocolErrorPredicate? isProtocolError,
    Random? random,
  }) : _loadPendingNoteIds = loadPendingNoteIds,
       _syncNote = syncNote,
       _isNoteActive = isNoteActive,
       _now = now ?? DateTime.now,
       _random = random ?? Random(),
       _backoffForAttempt = backoffForAttempt,
       _isProtocolError = isProtocolError ?? _defaultIsProtocolError;

  final PendingNoteIdsLoader _loadPendingNoteIds;
  final NoteSyncRunner _syncNote;
  final NoteActivePredicate _isNoteActive;
  final SyncClock _now;
  final SyncBackoff? _backoffForAttempt;
  final SyncProtocolErrorPredicate _isProtocolError;
  final Random _random;

  final Map<String, _RetryState> _retryByNote = {};
  final Set<String> _protocolSuppressedNotes = {};

  Future<void> _drainTail = Future<void>.value();
  Timer? _retryTimer;
  bool _disposed = false;

  /// Runs one serialized pass over all durable note-operation work.
  Future<void> drain() {
    if (_disposed) return Future<void>.value();
    final run = _drainTail.then((_) => _drainOnce());
    _drainTail = run.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return run;
  }

  /// Signals that an external condition changed, e.g. connectivity or
  /// foreground state. Meaningful wakes clear transient/protocol suppression
  /// so durable work is retried immediately.
  void wake({bool resetBackoff = true}) {
    if (_disposed) return;
    if (resetBackoff) {
      _retryByNote.clear();
      _protocolSuppressedNotes.clear();
      _retryTimer?.cancel();
      _retryTimer = null;
    }
    unawaited(drain());
  }

  Future<void> _drainOnce() async {
    if (_disposed) return;
    final noteIds = await _loadPendingNoteIds();
    if (_disposed) return;

    for (final noteId in noteIds) {
      if (_disposed) return;
      if (_isNoteActive(noteId)) continue;
      if (_protocolSuppressedNotes.contains(noteId)) continue;

      final retry = _retryByNote[noteId];
      if (retry != null && _now().isBefore(retry.nextAttemptAt)) {
        continue;
      }

      try {
        final result = await _syncNote(noteId);
        if (result.isBlocked) {
          _recordTransientFailure(noteId);
          continue;
        }
        _retryByNote.remove(noteId);
        _protocolSuppressedNotes.remove(noteId);
      } catch (error) {
        if (_isProtocolError(error)) {
          _retryByNote.remove(noteId);
          _protocolSuppressedNotes.add(noteId);
        } else {
          _recordTransientFailure(noteId);
        }
      }
    }

    _scheduleRetryTimer();
  }

  void _recordTransientFailure(String noteId) {
    final previousAttempt = _retryByNote[noteId]?.attempt ?? 0;
    final attempt = previousAttempt + 1;
    final delay = _backoffForAttempt?.call(attempt) ?? _defaultBackoff(attempt);
    _retryByNote[noteId] = _RetryState(
      attempt: attempt,
      nextAttemptAt: _now().add(delay),
    );
  }

  Duration _defaultBackoff(int attempt) {
    const seconds = [1, 2, 5, 10, 30, 60];
    final index = (attempt - 1).clamp(0, seconds.length - 1);
    final jitterMs = _random.nextInt(251);
    return Duration(seconds: seconds[index], milliseconds: jitterMs);
  }

  void _scheduleRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = null;
    if (_disposed || _retryByNote.isEmpty) return;

    DateTime? nextAttemptAt;
    for (final retry in _retryByNote.values) {
      if (nextAttemptAt == null || retry.nextAttemptAt.isBefore(nextAttemptAt)) {
        nextAttemptAt = retry.nextAttemptAt;
      }
    }
    if (nextAttemptAt == null) return;

    var delay = nextAttemptAt.difference(_now());
    if (delay.isNegative) delay = Duration.zero;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (!_disposed) unawaited(drain());
    });
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _drainTail;
  }

  static bool _defaultIsProtocolError(Object error) {
    if (error is FormatException || error is StateError) return true;
    if (error is NoteOperationsException) {
      final status = error.statusCode;
      if (status != null) return status >= 400 && status < 500;
      return error.errorCode != 'NETWORK_ERROR';
    }
    if (error is DioException) {
      final status = error.response?.statusCode;
      return status != null && status >= 400 && status < 500;
    }
    return false;
  }
}

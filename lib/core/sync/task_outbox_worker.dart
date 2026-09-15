import 'dart:async';
import 'dart:math';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/sync/sync_retry_policy.dart';

typedef PendingTaskIdsLoader = Future<List<String>> Function();
typedef TaskSyncRunner = Future<void> Function(String taskId);
typedef TaskSyncClock = DateTime Function();
typedef TaskSyncBackoff = Duration Function(int attempt);
typedef TaskProtocolErrorPredicate = bool Function(Object error);

class _TaskRetryState {
  const _TaskRetryState({required this.attempt, required this.nextAttemptAt});

  final int attempt;
  final DateTime nextAttemptAt;
}

/// Drains standalone-task mutations after local writes, app restarts and
/// transient network failures.
class TaskOutboxWorker {
  TaskOutboxWorker({
    required PendingTaskIdsLoader loadPendingTaskIds,
    required TaskSyncRunner syncTask,
    TaskSyncClock? now,
    TaskSyncBackoff? backoffForAttempt,
    TaskProtocolErrorPredicate? isProtocolError,
    Random? random,
  }) : _loadPendingTaskIds = loadPendingTaskIds,
       _syncTask = syncTask,
       _now = now ?? DateTime.now,
       _backoffForAttempt = backoffForAttempt,
       _isProtocolError = isProtocolError ?? _defaultIsProtocolError,
       _random = random ?? Random();

  final PendingTaskIdsLoader _loadPendingTaskIds;
  final TaskSyncRunner _syncTask;
  final TaskSyncClock _now;
  final TaskSyncBackoff? _backoffForAttempt;
  final TaskProtocolErrorPredicate _isProtocolError;
  final Random _random;

  final Map<String, _TaskRetryState> _retryByTask = {};
  final Set<String> _protocolSuppressedTasks = {};
  Future<void> _drainTail = Future<void>.value();
  Timer? _retryTimer;
  bool _disposed = false;

  Future<void> drain() {
    if (_disposed) return Future<void>.value();
    final run = _drainTail.then((_) => _drainOnce());
    _drainTail = run.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return run;
  }

  void wake({bool resetBackoff = true}) {
    if (_disposed) return;
    if (resetBackoff) {
      _retryByTask.clear();
      _protocolSuppressedTasks.clear();
      _retryTimer?.cancel();
      _retryTimer = null;
    }
    unawaited(drain());
  }

  Future<void> _drainOnce() async {
    if (_disposed) return;
    final taskIds = await _loadPendingTaskIds();
    for (final taskId in taskIds) {
      if (_disposed) return;
      if (!_isEligibleForAttempt(taskId)) continue;
      try {
        await _syncTask(taskId);
        _clearFailureState(taskId);
      } catch (error) {
        if (_isProtocolError(error)) {
          _retryByTask.remove(taskId);
          _protocolSuppressedTasks.add(taskId);
        } else {
          _recordTransientFailure(taskId);
        }
      }
    }
    _scheduleRetryTimer();
  }

  bool _isEligibleForAttempt(String taskId) {
    if (_protocolSuppressedTasks.contains(taskId)) return false;
    final retry = _retryByTask[taskId];
    return retry == null || !_now().isBefore(retry.nextAttemptAt);
  }

  void _clearFailureState(String taskId) {
    _retryByTask.remove(taskId);
    _protocolSuppressedTasks.remove(taskId);
  }

  void _recordTransientFailure(String taskId) {
    final previousAttempt = _retryByTask[taskId]?.attempt ?? 0;
    final attempt = previousAttempt + 1;
    final delay =
        _backoffForAttempt?.call(attempt) ??
        syncRetryDelayForAttempt(attempt) +
            Duration(milliseconds: _random.nextInt(251));
    _retryByTask[taskId] = _TaskRetryState(
      attempt: attempt,
      nextAttemptAt: _now().add(delay),
    );
  }

  void _scheduleRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = null;
    if (_disposed || _retryByTask.isEmpty) return;
    DateTime? nextAttemptAt;
    for (final retry in _retryByTask.values) {
      if (nextAttemptAt == null ||
          retry.nextAttemptAt.isBefore(nextAttemptAt)) {
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
    if (error is ApiException) {
      final status = error.statusCode;
      if (status == null) return false;
      return status >= 400 &&
          status < 500 &&
          status != 401 &&
          status != 408 &&
          status != 429;
    }
    return false;
  }
}

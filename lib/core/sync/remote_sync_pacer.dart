import 'dart:async';

import 'package:supanotes/core/sync/sync_retry_policy.dart';

/// Decides when the app-wide remote sync (change feed) runs next.
///
/// The feed used to be fetched every two seconds for as long as the process
/// lived, including while the app was in the background and when nothing had
/// changed for hours. The pacer keeps the two-second cadence only while it
/// matters (recent remote changes, or a note open for editing), backs off to
/// [idleInterval] when the feed is quiet, stops entirely while the app is in
/// the background, and can be woken immediately (app resume, connectivity,
/// local edits).
final class RemoteSyncPacer {
  RemoteSyncPacer({
    this.activeInterval = const Duration(seconds: 2),
    this.idleInterval = const Duration(seconds: 30),
  }) : _interval = activeInterval;

  final Duration activeInterval;
  final Duration idleInterval;

  Duration _interval;
  bool _foreground = true;
  bool _disposed = false;
  Completer<void>? _wake;
  Timer? _timer;

  /// Delay before the next run when nothing wakes the pacer earlier.
  Duration get nextDelay => _interval;

  bool get isForeground => _foreground;

  /// Records a successful run. [changed] means the feed delivered changes;
  /// [editing] means a note is open, where remote edits should arrive fast.
  void recordSuccess({required bool changed, required bool editing}) {
    if (changed || editing) {
      _interval = activeInterval;
      return;
    }
    final doubled = _interval * 2;
    _interval = doubled > idleInterval ? idleInterval : doubled;
  }

  /// Records the [attempt]-th consecutive failure.
  void recordFailure(int attempt) {
    _interval = syncRetryDelayForAttempt(attempt);
  }

  /// Foreground runs on the pacer's schedule; background suspends it.
  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (foreground) wake();
  }

  /// Runs the next sync now and restores the active cadence.
  void wake() {
    _interval = activeInterval;
    _completeWait();
  }

  /// Completes when the next run is due: after [nextDelay], or earlier when
  /// woken, and never while the app is in the background.
  Future<void> waitForNextRun() async {
    if (_disposed) return;
    await _wait(_foreground ? _interval : null);
    while (!_foreground && !_disposed) {
      await _wait(null);
    }
  }

  Future<void> _wait(Duration? delay) {
    final completer = _wake = Completer<void>();
    _timer?.cancel();
    if (delay != null) _timer = Timer(delay, _completeWait);
    return completer.future;
  }

  void _completeWait() {
    _timer?.cancel();
    _timer = null;
    final completer = _wake;
    _wake = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  void dispose() {
    _disposed = true;
    _completeWait();
  }
}

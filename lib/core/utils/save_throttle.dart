import 'dart:async';

/// Concurrency-safe debounced save with retry.
///
/// Apple Notes-style autosave requires that:
/// 1. Rapid edits coalesce into a single save (debounce).
/// 2. An in-flight save from an older edit cannot overwrite a newer one
///    (generation counter).
/// 3. Transient storage failures don't surface to the user (silent retry).
/// 4. When the user leaves the screen, the most recent edit is flushed
///    immediately, bypassing the debounce.
///
/// This class owns a debounce [Timer] and a monotonic [int] generation
/// counter. Callers pass the current generation to [schedule] or [flush];
/// any operation tied to a stale generation is discarded.
class SaveThrottle {
  SaveThrottle({
    this.debounce = const Duration(milliseconds: 500),
    this.maxAttempts = 3,
    this.retryDelays = const [
      Duration(milliseconds: 100),
      Duration(milliseconds: 300),
      Duration(milliseconds: 500),
    ],
  });

  final Duration debounce;
  final int maxAttempts;
  final List<Duration> retryDelays;

  Timer? _timer;
  int _generation = 0;

  /// Bumps the generation counter and returns the new value.
  int nextGeneration() => ++_generation;

  /// Schedules [operation] to run after the debounce window. If another
  /// call to [schedule] or [flush] happens before the window elapses,
  /// the pending operation is cancelled.
  ///
  /// [generation] should come from [nextGeneration]; the operation only
  /// runs if it matches the current generation at fire time.
  void schedule({
    required int generation,
    required Future<void> Function() operation,
  }) {
    _timer?.cancel();
    _timer = Timer(debounce, () {
      _timer = null;
      _runIfCurrent(generation, operation);
    });
  }

  /// Cancels the pending debounce timer and runs [operation] immediately
  /// if [generation] is still current. Returns the [Future] from [operation]
  /// so callers can await the flush.
  Future<void> flush({
    required int generation,
    required Future<void> Function() operation,
  }) async {
    _timer?.cancel();
    _timer = null;
    if (generation != _generation) return;
    await _runIfCurrent(generation, operation);
  }

  /// Runs [operation] through the retry loop. If [operation] is still
  /// tied to the current generation after all retries, the result
  /// (success or silent failure) is returned. Otherwise, the call is
  /// discarded before any work begins.
  Future<void> _runIfCurrent(
    int generation,
    Future<void> Function() operation,
  ) async {
    if (generation != _generation) return;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await operation();
        return;
      } catch (_) {
        if (attempt == maxAttempts - 1) return;
        await Future.delayed(retryDelays[attempt]);
      }
    }
  }

  /// Releases the debounce timer. Call from `dispose`.
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

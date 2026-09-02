/// Shared retry schedule for sync workers.
///
/// The first failure waits one second, then the delay grows to a maximum of
/// one minute. Callers may add jitter when several independent notes retry at
/// the same time.
const _syncRetryDelays = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 5),
  Duration(seconds: 10),
  Duration(seconds: 30),
  Duration(seconds: 60),
];

/// Returns the bounded delay for a one-based failed-attempt count.
Duration syncRetryDelayForAttempt(int attempt) {
  final index = (attempt - 1).clamp(0, _syncRetryDelays.length - 1);
  return _syncRetryDelays[index];
}

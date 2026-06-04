/// App-wide timing and limit constants.
class AppConstants {
  AppConstants._();

  static const String appName = 'SupaNotes';

  /// How often the background sync service runs while online.
  static const int syncIntervalSeconds = 30;

  /// Debounce window after the last editor change before triggering an
  /// auto-save to local Drift storage.
  static const int autoSaveDebounceMs = 2000;

  /// Inactivity window after which the agent chat session is rotated.
  static const int sessionTimeoutMinutes = 30;

  /// Maximum number of consecutive tool calls the agent can issue before the
  /// loop is halted server-side.
  static const int maxToolIterations = 5;
}

/// App-wide timing and limit constants.
class AppConstants {
  AppConstants._();

  static const String appName = 'SupaNotes';

  /// How often the background sync service runs while online.
  static const int syncIntervalSeconds = 30;

  /// Debounce window after the last editor change before triggering an
  /// auto-save to local Drift storage.
  static const int autoSaveDebounceMs = 500;

  /// Inactivity window after which the agent chat session is rotated.
  static const int sessionTimeoutMinutes = 30;

  /// Maximum number of consecutive tool calls the agent can issue before the
  /// loop is halted server-side.
  static const int maxToolIterations = 5;

  /// Maximum characters for the note excerpt preview shown in note cards.
  static const int noteExcerptMaxLength = 120;

  /// Debounce window for search input keystrokes before firing a query.
  static const int searchDebounceMs = 300;
}

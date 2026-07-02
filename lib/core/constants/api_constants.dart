/// HTTP and API constants.
///
/// In production these values can be injected from build-time environment
/// variables using `--dart-define=API_BASE_URL=...`.
///
/// During local development the [setup-dev-env.ps1] script auto-detects the
/// target (emulator, physical device, or desktop) and writes the correct URL
/// to `.vscode/.dart-define.json`, which is then passed via
/// `--dart-define-from-file` in launch.json.
///
/// In dev:
/// - **Android emulator**: traffic is routed through the host machine at
///   `10.0.2.2`.
/// - **Android physical device**: use `adb reverse tcp:8080 tcp:8080` so the
///   device can reach the host via `localhost`.
/// - **Desktop / iOS simulator**: use `localhost` directly.
class ApiConstants {
  ApiConstants._();

  static const String _envBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static const String _prodBaseUrl =
      'https://backend-winter-waterfall-5807.fly.dev/api/v1';

  static String get baseUrl {
    if (_envBaseUrl.isNotEmpty) {
      return _envBaseUrl;
    }
    // Fall back to production when no dart-define is provided.
    // For local backend development, pass --dart-define=API_BASE_URL=http://localhost:8080/api/v1
    return _prodBaseUrl;
  }

  static const int connectTimeoutMs = 30000; // 30s for initial connection
  static const int receiveTimeoutMs = 30000; // 30s for response
}

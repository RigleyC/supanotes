import 'package:flutter/foundation.dart';

import 'package:supanotes/core/constants/platform_info.dart';

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

  static const String _envBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');

  static String get baseUrl {
    if (_envBaseUrl.isNotEmpty) {
      return _envBaseUrl;
    }
    if (kIsWeb) {
      return 'http://localhost:8080/api/v1';
    }
    if (isAndroid) {
      // Works for both emulator (10.0.2.2) and physical device with
      // `adb reverse tcp:8080 tcp:8080` (localhost).
      return 'http://localhost:8080/api/v1';
    }
    return 'http://localhost:8080/api/v1';
  }

  static const int connectTimeoutMs = 30000; // 30s for initial connection
  static const int receiveTimeoutMs = 30000; // 30s for response
}

import 'package:flutter/foundation.dart';

import 'package:supanotes/core/constants/platform_info.dart';

/// HTTP and API constants.
///
/// In production these values can be injected from build-time environment
/// variables using `--dart-define=API_BASE_URL=...`.
///
/// In dev, Android emulator traffic is routed through the host machine at
/// `10.0.2.2`, while desktop and iOS simulator use `localhost`.
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
      return 'http://10.0.2.2:8080/api/v1';
    }
    return 'http://localhost:8080/api/v1';
  }

  static const int connectTimeoutMs = 10000;
  static const int receiveTimeoutMs = 15000;
}

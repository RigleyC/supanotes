/// HTTP and API constants.
///
/// In production these values will be injected from build-time environment
/// variables (e.g. `--dart-define=API_BASE_URL=...`). The dev defaults assume
/// the Go backend is running locally on port 8080.
class ApiConstants {
  ApiConstants._();

  static const String baseUrl = 'http://localhost:8080/api/v1';
  static const int connectTimeoutMs = 10000;
  static const int receiveTimeoutMs = 15000;
}

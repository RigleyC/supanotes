import 'package:supanotes/core/api/auth_interceptor.dart';

/// Adapts the old storage-shaped test setup to the production interceptor
/// contract without exposing that compatibility path from lib/.
AuthInterceptor buildTestAuthInterceptor({
  required Future<String?> Function() getAccessToken,
  required Future<String?> Function() getRefreshToken,
  required Future<void> Function({
    required String accessToken,
    required String refreshToken,
  })
  saveTokens,
  required AuthFailureHandler onAuthFailure,
  required RefreshHandler onRefresh,
  required ReplayHandler replay,
}) {
  return AuthInterceptor(
    getAccessToken: getAccessToken,
    onAuthFailure: onAuthFailure,
    onRefresh: onRefresh,
    refreshSession: (refresh) async {
      final refreshToken = await getRefreshToken();
      if (refreshToken == null) return null;
      final tokens = await refresh(refreshToken);
      if (tokens == null) return null;
      await saveTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      return tokens;
    },
    replay: replay,
  );
}

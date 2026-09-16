import 'package:supanotes/core/api/auth_interceptor.dart';
import 'package:supanotes/core/auth/auth_tokens.dart';

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
    refreshSession: () async {
      final refreshToken = await getRefreshToken();
      if (refreshToken == null) return null;
      final tokens = await onRefresh(refreshToken);
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

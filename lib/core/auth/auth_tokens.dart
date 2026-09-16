/// Credentials shared by the authenticated session and its HTTP transport.
typedef AuthTokenPair = ({String accessToken, String refreshToken});

typedef AuthTokenState = ({String? accessToken, String? refreshToken});

typedef RefreshHandler = Future<AuthTokenPair?> Function(String refreshToken);

typedef RefreshSessionHandler =
    Future<AuthTokenPair?> Function(RefreshHandler refresh);

typedef SessionRefreshHandler = Future<AuthTokenPair?> Function();

/// Pure-function redirect rule consumed by the [GoRouter] in
/// `app_router.dart`.
///
/// Kept separate from the router so the rule can be unit-tested without
/// spinning up a whole router, and so the test can import the function
/// without pulling in the rest of the routing configuration.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/features/auth/domain/auth_state.dart';

/// Computes the redirect target for [currentLocation] under [authState].
///
/// Returns:
///   * `null` — no redirect (used while auth is still loading).
///   * `'/login'` — user is unauthenticated and tried to leave the auth
///     flow.
///   * `'/home'` — user is authenticated and tried to re-enter the auth
///     flow.
///
/// Anything that is neither an auth route nor a protected route falls
/// through and is left to the route table.
String? authGuardRedirect({
  required String currentLocation,
  required AsyncValue<AuthState> authState,
}) {
  // The splash is always accessible — it is the launch interstitial that
  // renders while the auth controller resolves, and a hard redirect
  // away from it would cause a visible flash of /login.
  if (currentLocation == '/') return null;

  final isAuthRoute =
      currentLocation == '/login' || currentLocation == '/register';
  return authState.when(
    data: (auth) {
      if (auth is AuthAuthenticated && isAuthRoute) return '/home';
      if (auth is AuthUnauthenticated && !isAuthRoute) return '/login';
      return null;
    },
    loading: () => null,
    error: (_, __) => '/login',
  );
}

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
/// While the controller is loading the router stays put so the user does
/// not see a flash of /login before the session check completes.
String? authGuardRedirect({
  required String currentLocation,
  required AsyncValue<AuthState> authState,
}) {
  return authState.when(
    data: (auth) {
      if (auth is AuthAuthenticated) {
        if (currentLocation == '/' ||
            currentLocation == '/login' ||
            currentLocation == '/register') {
          return '/home';
        }
        return null;
      }
      if (currentLocation == '/login' || currentLocation == '/register') {
        return null;
      }
      return '/login';
    },
    loading: () => null,
    error: (_, __) => '/login',
  );
}

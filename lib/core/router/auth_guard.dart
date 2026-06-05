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
///   * `null` — no redirect (used while auth is still loading on `/`).
///   * `'/login'` — user is unauthenticated and tried to leave the auth
///     flow.
///   * `'/home'` — user is authenticated and tried to re-enter the auth
///     flow.
///
/// The splash (`/`) is the only route that has different behaviour by
/// auth phase: while the controller is still loading, stay put so the
/// user does not see a flash of /login; once the controller resolves,
/// bounce to the correct landing route.
String? authGuardRedirect({
  required String currentLocation,
  required AsyncValue<AuthState> authState,
}) {
  if (currentLocation == '/') {
    return authState.when(
      data: (auth) {
        if (auth is AuthInitial) return null;
        return auth is AuthAuthenticated ? '/home' : '/login';
      },
      loading: () => null,
      error: (_, __) => '/login',
    );
  }

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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/auth/domain/auth_state.dart';
import 'package:supanotes/core/router/auth_guard.dart';

const _login = '/login';
const _register = '/register';
const _home = '/home';
const _splash = '/';

void main() {
  group('authGuardRedirect', () {
    test('returns null while auth is still loading (do not bounce)', () {
      const loading = AsyncValue<AuthState>.loading();
      expect(authGuardRedirect(currentLocation: _home, authState: loading),
          isNull);
      expect(
          authGuardRedirect(currentLocation: _login, authState: loading),
          isNull);
      expect(redirectFor(_splash, loading), isNull);
    });

    test('redirects to /login when unauthenticated user hits a protected route',
        () {
      const unauth = AsyncValue<AuthState>.data(AuthUnauthenticated());
      expect(authGuardRedirect(currentLocation: _home, authState: unauth),
          _login);
    });

    test('leaves the user on /login when they are already there', () {
      const unauth = AsyncValue<AuthState>.data(AuthUnauthenticated());
      expect(authGuardRedirect(currentLocation: _login, authState: unauth),
          isNull);
    });

    test('leaves the user on /register when they are already there', () {
      const unauth = AsyncValue<AuthState>.data(AuthUnauthenticated());
      expect(authGuardRedirect(currentLocation: _register, authState: unauth),
          isNull);
    });

    test('lets an unauthenticated user stay on the splash', () {
      const unauth = AsyncValue<AuthState>.data(AuthUnauthenticated());
      expect(redirectFor(_splash, unauth), isNull);
    });

    test('redirects to /home when an authenticated user revisits /login', () {
      const auth = AsyncValue<AuthState>.data(
        AuthAuthenticated(userId: 'u-1', email: 'a@b.com', name: 'Alice'),
      );
      expect(authGuardRedirect(currentLocation: _login, authState: auth),
          _home);
    });

    test('redirects to /home when an authenticated user revisits /register',
        () {
      const auth = AsyncValue<AuthState>.data(
        AuthAuthenticated(userId: 'u-1', email: 'a@b.com', name: 'Alice'),
      );
      expect(authGuardRedirect(currentLocation: _register, authState: auth),
          _home);
    });

    test('lets an authenticated user stay on /home', () {
      const auth = AsyncValue<AuthState>.data(
        AuthAuthenticated(userId: 'u-1', email: 'a@b.com', name: 'Alice'),
      );
      expect(authGuardRedirect(currentLocation: _home, authState: auth),
          isNull);
    });

    test('lets an authenticated user stay on the splash', () {
      const auth = AsyncValue<AuthState>.data(
        AuthAuthenticated(userId: 'u-1', email: 'a@b.com', name: 'Alice'),
      );
      expect(redirectFor(_splash, auth), isNull);
    });

    test('treats the AuthInitial data state as not yet routable', () {
      // Per the spec, the router does not redirect while AuthInitial is
      // the current state, so the user is not bounced to /login before
      // we know whether they have a saved session.
      const initial = AsyncValue<AuthState>.data(AuthInitial());
      expect(redirectFor(_home, initial), isNull);
      expect(redirectFor(_splash, initial), isNull);
      expect(redirectFor(_login, initial), isNull);
    });

    test('falls back to /login when the auth provider is in an error state',
        () {
      final errored = AsyncValue<AuthState>.error(
        StateError('storage unavailable'),
        StackTrace.current,
      );
      expect(authGuardRedirect(currentLocation: _home, authState: errored),
          _login);
    });
  });
}

/// Convenience: the redirect is the same regardless of location for the
/// splash. Wrapped so tests read more clearly.
String? redirectFor(String currentLocation, AsyncValue<AuthState> authState) {
  return authGuardRedirect(
    currentLocation: currentLocation,
    authState: authState,
  );
}

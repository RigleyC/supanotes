import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/auth/domain/user.dart';
import 'package:supanotes/core/router/auth_guard.dart';

const _login = '/login';
const _register = '/register';
const _home = '/home';
const _splash = '/';

void main() {
  group('authGuardRedirect', () {
    test('returns null while auth is still loading (do not bounce)', () {
      const loading = AsyncValue<User?>.loading();
      expect(authGuardRedirect(currentLocation: _home, authState: loading),
          isNull);
      expect(
          authGuardRedirect(currentLocation: _login, authState: loading),
          isNull);
      expect(redirectFor(_splash, loading), isNull);
    });

    test('redirects to /login when unauthenticated user hits a protected route',
        () {
      final unauth = AsyncValue<User?>.data(null);
      expect(authGuardRedirect(currentLocation: _home, authState: unauth),
          _login);
    });

    test('leaves the user on /login when they are already there', () {
      final unauth = AsyncValue<User?>.data(null);
      expect(authGuardRedirect(currentLocation: _login, authState: unauth),
          isNull);
    });

    test('leaves the user on /register when they are already there', () {
      final unauth = AsyncValue<User?>.data(null);
      expect(authGuardRedirect(currentLocation: _register, authState: unauth),
          isNull);
    });

    test('redirects to /login when an unauthenticated user lands on /', () {
      final unauth = AsyncValue<User?>.data(null);
      expect(redirectFor(_splash, unauth), _login);
    });

    test('redirects to /home when an authenticated user lands on /', () {
      final auth = AsyncValue<User?>.data(
        const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
      );
      expect(redirectFor(_splash, auth), _home);
    });

    test('redirects to /home when an authenticated user revisits /login', () {
      final auth = AsyncValue<User?>.data(
        const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
      );
      expect(authGuardRedirect(currentLocation: _login, authState: auth),
          _home);
    });

    test('redirects to /home when an authenticated user revisits /register',
        () {
      final auth = AsyncValue<User?>.data(
        const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
      );
      expect(authGuardRedirect(currentLocation: _register, authState: auth),
          _home);
    });

    test('lets an authenticated user stay on /home', () {
      final auth = AsyncValue<User?>.data(
        const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
      );
      expect(authGuardRedirect(currentLocation: _home, authState: auth),
          isNull);
    });

    test('falls back to /login when the auth provider is in an error state',
        () {
      final errored = AsyncValue<User?>.error(
        StateError('storage unavailable'),
        StackTrace.current,
      );
      expect(authGuardRedirect(currentLocation: _home, authState: errored),
          _login);
    });
  });
}

String? redirectFor(String currentLocation, AsyncValue<User?> authState) {
  return authGuardRedirect(
    currentLocation: currentLocation,
    authState: authState,
  );
}

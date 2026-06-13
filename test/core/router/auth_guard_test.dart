import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/auth/domain/user.dart';
import 'package:supanotes/core/router/auth_guard.dart';

void main() {
  group('authGuardRedirect', () {
    test('redirects to /splash while auth is loading on a protected route', () {
      const loading = AsyncValue<User?>.loading();
      expect(
        authGuardRedirect(currentLocation: AppRoutes.home, authState: loading),
        AppRoutes.splash,
      );
      expect(
        authGuardRedirect(currentLocation: AppRoutes.login, authState: loading),
        AppRoutes.splash,
      );
      expect(redirectFor(AppRoutes.home, loading), AppRoutes.splash);
    });

    test('leaves the user on /splash while loading', () {
      const loading = AsyncValue<User?>.loading();
      expect(
        authGuardRedirect(currentLocation: AppRoutes.splash, authState: loading),
        isNull,
      );
    });

    test('redirects from /splash to /home when authenticated (no persisted route)',
        () {
      final auth = AsyncValue<User?>.data(
        const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
      );
      expect(
        authGuardRedirect(currentLocation: AppRoutes.splash, authState: auth),
        AppRoutes.home,
      );
    });

    test('redirects from /splash to the persisted route when authenticated', () {
      final auth = AsyncValue<User?>.data(
        const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
      );
      expect(
        authGuardRedirect(
          currentLocation: AppRoutes.splash,
          authState: auth,
          persistedLocation: '/notes/note-1',
        ),
        '/notes/note-1',
      );
    });

    test('falls back to /home when persisted route is /splash', () {
      final auth = AsyncValue<User?>.data(
        const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
      );
      expect(
        authGuardRedirect(
          currentLocation: AppRoutes.splash,
          authState: auth,
          persistedLocation: AppRoutes.splash,
        ),
        AppRoutes.home,
      );
    });

    test('redirects from /splash to /login when unauthenticated', () {
      final unauth = AsyncValue<User?>.data(null);
      expect(
        authGuardRedirect(currentLocation: AppRoutes.splash, authState: unauth),
        AppRoutes.login,
      );
    });

    test('redirects to /login when unauthenticated user hits a protected route',
        () {
      final unauth = AsyncValue<User?>.data(null);
      expect(authGuardRedirect(currentLocation: AppRoutes.home, authState: unauth),
          AppRoutes.login);
    });

    test('leaves the user on /login when they are already there', () {
      final unauth = AsyncValue<User?>.data(null);
      expect(authGuardRedirect(currentLocation: AppRoutes.login, authState: unauth),
          isNull);
    });

    test('leaves the user on /register when they are already there', () {
      final unauth = AsyncValue<User?>.data(null);
      expect(authGuardRedirect(currentLocation: AppRoutes.register, authState: unauth),
          isNull);
    });

    test('redirects to /login when unauthenticated user lands on protected route', () {
      final unauth = AsyncValue<User?>.data(null);
      expect(redirectFor(AppRoutes.home, unauth), AppRoutes.login);
    });

    test('redirects to /home when an authenticated user revisits /login', () {
      final auth = AsyncValue<User?>.data(
        const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
      );
      expect(authGuardRedirect(currentLocation: AppRoutes.login, authState: auth),
          AppRoutes.home);
    });

    test('redirects to /home when an authenticated user revisits /register',
        () {
      final auth = AsyncValue<User?>.data(
        const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
      );
      expect(authGuardRedirect(currentLocation: AppRoutes.register, authState: auth),
          AppRoutes.home);
    });

    test('lets an authenticated user stay on /home', () {
      final auth = AsyncValue<User?>.data(
        const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
      );
      expect(authGuardRedirect(currentLocation: AppRoutes.home, authState: auth),
          isNull);
    });

    test('falls back to /login when the auth provider is in an error state',
        () {
      final errored = AsyncValue<User?>.error(
        StateError('storage unavailable'),
        StackTrace.current,
      );
      expect(authGuardRedirect(currentLocation: AppRoutes.home, authState: errored),
          AppRoutes.login);
    });
  });
}

String? redirectFor(String currentLocation, AsyncValue<User?> authState) {
  return authGuardRedirect(
    currentLocation: currentLocation,
    authState: authState,
  );
}

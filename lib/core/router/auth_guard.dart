library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/auth/domain/user.dart';

String? authGuardRedirect({
  required String currentLocation,
  required AsyncValue<User?> authState,
  String? persistedLocation,
}) {
  debugPrint(
    '[LastRoute] authGuardRedirect currentLocation=$currentLocation persistedLocation=$persistedLocation authState=${authState.runtimeType}',
  );
  final isAuthPage =
      currentLocation == AppRoutes.login ||
      currentLocation == AppRoutes.register;

  String resolveDestination() {
    if (persistedLocation != null &&
        persistedLocation != AppRoutes.splash &&
        persistedLocation != AppRoutes.login &&
        persistedLocation != AppRoutes.register) {
      return persistedLocation;
    }
    return AppRoutes.home;
  }

  return authState.when(
    data: (user) {
      // Coming from the splash screen — decide where to go.
      if (currentLocation == AppRoutes.splash) {
        if (user == null) return AppRoutes.login;
        // Restore last route, falling back to /home.
        return resolveDestination();
      }

      if (user != null) {
        // Authenticated user on login/register → go to destination.
        if (isAuthPage) return resolveDestination();
        // Authenticated user anywhere else → stay.
        return null;
      }

      // Unauthenticated user on a public page → stay.
      if (isAuthPage) return null;
      // Unauthenticated user on a protected page → login.
      return AppRoutes.login;
    },
    loading: () {
      // While auth is resolving, stay on login/register or splash so we don't
      // interrupt an active login attempt or the splash screen.
      if (isAuthPage || currentLocation == AppRoutes.splash) {
        return null;
      }
      // If we are on a protected route during cold start loading, go to splash.
      // This prevents UI providers from crashing due to missing user id.
      // Once auth resolves, we will restore the route using persistedLocation.
      return AppRoutes.splash;
    },
    error: (_, _) {
      // If on login/register, stay there to show the error snackbar.
      if (isAuthPage) return null;
      return AppRoutes.login;
    },
  );
}

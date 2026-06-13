library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/auth/domain/user.dart';

String? authGuardRedirect({
  required String currentLocation,
  required AsyncValue<User?> authState,
}) {
  return authState.when(
    data: (user) {
      // Coming from the splash screen — decide where to go.
      if (currentLocation == AppRoutes.splash) {
        return user != null ? AppRoutes.home : AppRoutes.login;
      }

      final isAuthPage = currentLocation == AppRoutes.login ||
          currentLocation == AppRoutes.register;

      if (user != null) {
        // Authenticated user on login/register → go home.
        if (isAuthPage) return AppRoutes.home;
        // Authenticated user anywhere else → stay.
        return null;
      }

      // Unauthenticated user on a public page → stay.
      if (isAuthPage) return null;
      // Unauthenticated user on a protected page → login.
      return AppRoutes.login;
    },
    loading: () {
      // While auth is resolving, show the splash only if the user is on a
      // login/register page (we don't want those visible during loading).
      // For any other route — including the persisted one — stay put so the
      // user sees their last screen while we check the session.
      final isAuthPage = currentLocation == AppRoutes.login ||
          currentLocation == AppRoutes.register;
      if (isAuthPage || currentLocation == AppRoutes.splash) {
        return AppRoutes.splash;
      }
      // Stay on the current (persisted) route while loading.
      return null;
    },
    error: (_, _) => AppRoutes.login,
  );
}

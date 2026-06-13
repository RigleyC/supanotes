library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/auth/domain/user.dart';

String? authGuardRedirect({
  required String currentLocation,
  required AsyncValue<User?> authState,
  /// The last persisted route from [LastRouteStore], if any.
  /// When provided and auth resolves on the splash, navigates here instead
  /// of always going to [AppRoutes.home].
  String? persistedLocation,
}) {
  return authState.when(
    data: (user) {
      if (currentLocation == AppRoutes.splash) {
        if (user == null) return AppRoutes.login;
        // Restore last route, falling back to /home.
        final destination = (persistedLocation != null &&
                persistedLocation != AppRoutes.splash &&
                persistedLocation != AppRoutes.login &&
                persistedLocation != AppRoutes.register)
            ? persistedLocation
            : AppRoutes.home;
        return destination;
      }
      final isAuthPage = currentLocation == AppRoutes.login ||
          currentLocation == AppRoutes.register;
      if (user != null) {
        if (isAuthPage) {
          return persistedLocation ?? AppRoutes.home;
        }
        return null;
      }
      if (isAuthPage) return null;
      return AppRoutes.login;
    },
    loading: () {
      if (currentLocation == AppRoutes.splash) return null;
      return AppRoutes.splash;
    },
    error: (_, _) => AppRoutes.login,
  );
}

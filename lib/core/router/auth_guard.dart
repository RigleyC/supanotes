library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/auth/domain/user.dart';

String? authGuardRedirect({
  required String currentLocation,
  required AsyncValue<User?> authState,
}) {
  final isAuthPage =
      currentLocation == AppRoutes.login ||
      currentLocation == AppRoutes.register;
  final isPublicShareLink = currentLocation.startsWith('/s/');

  return authState.when(
    data: (user) {
      if (currentLocation == AppRoutes.splash) {
        if (user == null) return AppRoutes.login;
        return AppRoutes.home;
      }

      if (user != null) {
        if (isAuthPage) return AppRoutes.home;
        return null;
      }

      if (isPublicShareLink) return null;

      if (isAuthPage) return null;
      return AppRoutes.login;
    },
    loading: () {
      if (isAuthPage ||
          isPublicShareLink ||
          currentLocation == AppRoutes.splash) {
        return null;
      }
      return AppRoutes.splash;
    },
    error: (_, _) {
      if (isAuthPage || isPublicShareLink) return null;
      return AppRoutes.login;
    },
  );
}

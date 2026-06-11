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
      final isAuthPage = currentLocation == AppRoutes.login ||
          currentLocation == AppRoutes.register;
      if (user != null) {
        if (isAuthPage) {
          return AppRoutes.home;
        }
        return null;
      }
      if (isAuthPage) return null;
      return AppRoutes.login;
    },
    loading: () => null,
    error: (_, _) => AppRoutes.login,
  );
}

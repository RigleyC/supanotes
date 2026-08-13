library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/auth/domain/user.dart';

String? authGuardRedirect({
  required String currentLocation,
  required AsyncValue<User?> authState,
}) {
  final isAuthPage = _isAuthPage(currentLocation);
  final isPublicShareLink = currentLocation.startsWith('/s/');

  return authState.when(
    data: (user) => _redirectForData(
      currentLocation: currentLocation,
      user: user,
      isAuthPage: isAuthPage,
      isPublicShareLink: isPublicShareLink,
    ),
    loading: () => _redirectWhileLoading(
      currentLocation: currentLocation,
      isAuthPage: isAuthPage,
      isPublicShareLink: isPublicShareLink,
    ),
    error: (_, _) => _redirectForError(
      isAuthPage: isAuthPage,
      isPublicShareLink: isPublicShareLink,
    ),
  );
}

bool _isAuthPage(String location) {
  return location == AppRoutes.login || location == AppRoutes.register;
}

String? _redirectForData({
  required String currentLocation,
  required User? user,
  required bool isAuthPage,
  required bool isPublicShareLink,
}) {
  if (currentLocation == AppRoutes.splash) {
    return user == null ? AppRoutes.login : AppRoutes.home;
  }
  if (user != null) return isAuthPage ? AppRoutes.home : null;
  if (isPublicShareLink || isAuthPage) return null;
  return AppRoutes.login;
}

String? _redirectWhileLoading({
  required String currentLocation,
  required bool isAuthPage,
  required bool isPublicShareLink,
}) {
  if (isAuthPage || isPublicShareLink || currentLocation == AppRoutes.splash) {
    return null;
  }
  return AppRoutes.splash;
}

String? _redirectForError({
  required bool isAuthPage,
  required bool isPublicShareLink,
}) {
  if (isAuthPage || isPublicShareLink) return null;
  return AppRoutes.login;
}

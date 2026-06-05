/// Convenience accessors for "the currently signed-in user".
///
/// `currentUserIdProvider` collapses the auth controller's `AsyncValue`
/// into a single nullable string that downstream code can watch without
/// having to deal with the loading / error states directly.
///
/// Repositories that touch user-owned data should depend on this provider
/// (or a derivative that throws when null) so that a sign-out automatically
/// tears the cached instance down via Riverpod's auto-dispose rules.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/auth/domain/auth_state.dart';

/// Current authenticated user id, or null if signed out / loading.
final currentUserIdProvider = Provider<String?>((ref) {
  final state = ref.watch(authControllerProvider);
  return state.maybeWhen(
    data: (s) => s is AuthAuthenticated ? s.userId : null,
    orElse: () => null,
  );
});

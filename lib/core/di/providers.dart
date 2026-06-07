/// Central dependency injection wiring for the SupaNotes app.
///
/// All Riverpod providers that form the DI graph are defined here so
/// there is a single, acyclic source of truth for "what depends on what".
///
/// Feature code should import this file to access providers rather than
/// declaring them inline within feature modules.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/auth_interceptor.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/data/auth_repository.dart';
import 'package:supanotes/features/auth/domain/auth_state.dart';
import 'package:supanotes/features/auth/presentation/controllers/auth_controller.dart';

// ---------------------------------------------------------------------------
// Auth local storage
// ---------------------------------------------------------------------------

/// Singleton [AuthLocalStorage] for the lifetime of the app.
final authLocalStorageProvider = Provider<AuthLocalStorage>((ref) {
  return AuthLocalStorage();
});

// ---------------------------------------------------------------------------
// API client
// ---------------------------------------------------------------------------

/// Single [ApiClient] with the auth interceptor wired in.
///
/// The [AuthInterceptor] is configured to call [AuthController.onSessionExpired]
/// when a token refresh fails, which flips the auth state to
/// [AuthUnauthenticated] and triggers a router redirect to /login.
final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(authLocalStorageProvider);
  final interceptor = AuthInterceptor(
    tokenStorage: storage,
    onAuthFailure: () async {
      ref.read(authControllerProvider.notifier).onSessionExpired();
    },
  );
  return ApiClient(authInterceptor: interceptor);
});

// ---------------------------------------------------------------------------
// Auth repository
// ---------------------------------------------------------------------------

/// Single [AuthRepository] wired to the shared [apiClientProvider].
final authRepositoryProvider = Provider<IAuthRepository>((ref) {
  return AuthRepository(
    apiClient: ref.watch(apiClientProvider),
    storage: ref.watch(authLocalStorageProvider),
  );
});

// ---------------------------------------------------------------------------
// Auth controller
// ---------------------------------------------------------------------------

/// Global [AuthController] — consumed by the router, the auth screens,
/// and any other widget that needs to know the current session.
final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);

/// DI bootstrap for the application.
///
/// Owns the *real* [ApiClient] provider and registers it with
/// `features/auth/domain/auth_state.dart` via [setApiClientProvider]
/// (so the auth repository can read it through the getter exposed
/// there without importing this file and creating a cycle).
///
/// Importing this library at the top of `main.dart` (and from the
/// test entry point) is what triggers the registration; the rest of
/// the app then reads the provider through the getter in the auth
/// state module.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/auth_interceptor.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/domain/auth_state.dart';

/// Builds the real [Provider<ApiClient>] and wires it into the auth
/// state module.
///
/// The [AuthInterceptor.onAuthFailure] callback is wired to the
/// [AuthController.onSessionExpired] notifier; the read of
/// [authControllerProvider] is deferred to invocation time (rather
/// than inside the factory body) so we do not introduce a synchronous
/// construction cycle between the api client, the auth repository and
/// the auth controller.
void registerApiClientProvider() {
  setApiClientProvider(
    Provider<ApiClient>((ref) {
      final AuthLocalStorage storage = ref.read(authLocalStorageProvider);
      return ApiClient(
        authInterceptor: AuthInterceptor(
          tokenStorage: storage,
          onAuthFailure: () =>
              ref.read(authControllerProvider.notifier).onSessionExpired(),
        ),
      );
    }),
  );
}

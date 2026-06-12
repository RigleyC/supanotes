/// Central dependency injection wiring for the SupaNotes app.
///
/// All Riverpod providers that form the DI graph are defined here so
/// there is a single, acyclic source of truth for "what depends on what".
///
/// Feature code should import this file to access providers rather than
/// declaring them inline within feature modules.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/auth_interceptor.dart';
import 'package:supanotes/core/constants/api_constants.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/data/auth_repository.dart';
import 'package:supanotes/features/auth/presentation/controllers/auth_controller.dart';
import 'package:supanotes/features/auth/domain/user.dart';

// ---------------------------------------------------------------------------
// Auth local storage
// ---------------------------------------------------------------------------

/// Singleton [AuthLocalStorage] for the lifetime of the app.
final authLocalStorageProvider = Provider<AuthLocalStorage>((ref) {
  return AuthLocalStorage();
});

// ---------------------------------------------------------------------------
// Raw Dio (no auth interceptor) for refresh + replay calls
// ---------------------------------------------------------------------------

/// A plain [Dio] instance without any interceptors, used internally for
/// the refresh HTTP call and for replaying original requests after a
/// successful refresh. Avoids the recursion that would occur if the
/// [AuthInterceptor]'s own [ApiClient] were used for these operations.
final _rawDioProvider = Provider<Dio>((ref) {
  final dio = Dio();
  dio.options
    ..baseUrl = ApiConstants.baseUrl
    ..connectTimeout = const Duration(
      milliseconds: ApiConstants.connectTimeoutMs,
    )
    ..receiveTimeout = const Duration(
      milliseconds: ApiConstants.receiveTimeoutMs,
    )
    ..contentType = Headers.jsonContentType
    ..responseType = ResponseType.json;
  return dio;
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
  final rawDio = ref.watch(_rawDioProvider);
  final interceptor = AuthInterceptor(
    tokenStorage: storage,
    onAuthFailure: () async {
      ref.read(authControllerProvider.notifier).onSessionExpired();
    },
    onRefresh: (refreshToken) async {
      try {
        final response = await rawDio.post<Map<String, dynamic>>(
          '/auth/refresh',
          data: {'refresh_token': refreshToken},
        );
        final data = response.data;
        if (data == null) return null;
        final newAccess = data['access_token'] as String?;
        final newRefresh = data['refresh_token'] as String?;
        if (newAccess == null || newRefresh == null) return null;
        return (accessToken: newAccess, refreshToken: newRefresh);
      } on DioException {
        return null;
      }
    },
    replay: (options) => rawDio.fetch<dynamic>(options),
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
///
/// State is [AsyncValue<User?>]: loading, data(user) → authenticated,
/// data(null) → unauthenticated, error → unauthenticated with feedback.
final authControllerProvider =
    NotifierProvider<AuthController, AsyncValue<User?>>(AuthController.new);

// ---------------------------------------------------------------------------
// Database DAOs
// ---------------------------------------------------------------------------

final tagsDaoProvider = Provider.autoDispose((ref) => ref.watch(appDatabaseProvider).tagsDao);

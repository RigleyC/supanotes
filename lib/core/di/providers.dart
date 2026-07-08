/// Central dependency injection wiring for the SupaNotes app.
///
/// All Riverpod providers that form the DI graph are defined here so
/// there is a single, acyclic source of truth for "what depends on what".
///
/// Feature code should import this file to access providers rather than
/// declaring them inline within feature modules.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/notifications/push_service.dart';
import 'package:supanotes/core/sync/yjs_sync_manager.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/data/auth_repository.dart';
import 'package:supanotes/features/auth/presentation/controllers/auth_controller.dart';
import 'package:supanotes/features/auth/domain/user.dart';

// ---------------------------------------------------------------------------
// API client
// ---------------------------------------------------------------------------

/// Single [ApiClient] with the auth interceptor wired in.
///
/// The [ApiClient] creates the [AuthInterceptor] internally and uses its
/// own [Dio] instance for refresh + replay calls. The interceptor's path
/// and retry guards prevent recursion — no separate raw Dio needed.
final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(authLocalStorageProvider);
  return ApiClient(
    getAccessToken: () => storage.getAccessToken(),
    getRefreshToken: () => storage.getRefreshToken(),
    saveTokens: ({required String accessToken, required String refreshToken}) =>
        storage.saveTokens(
          accessToken: accessToken,
          refreshToken: refreshToken,
        ),
    onAuthFailure: () async {
      ref.read(authControllerProvider.notifier).onSessionExpired();
    },
  );
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
final authControllerProvider = AsyncNotifierProvider<AuthController, User?>(
  AuthController.new,
);

final sessionResetProvider = StateProvider<int>((ref) => 0);

// ---------------------------------------------------------------------------
// Database DAOs
// ---------------------------------------------------------------------------

final tagsDaoProvider = Provider.autoDispose(
  (ref) => ref.watch(appDatabaseProvider).tagsDao,
);

// ---------------------------------------------------------------------------
// Push notification service
// ---------------------------------------------------------------------------

final pushServiceProvider = NotifierProvider<PushService, bool>(
  PushService.new,
);

// ---------------------------------------------------------------------------
// Yjs sync manager (local Yjs docs per note)
// ---------------------------------------------------------------------------

final yjsSyncManagerProvider = Provider<YjsSyncManager>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final mgr = YjsSyncManager(db: db);
  ref.onDispose(mgr.dispose);
  return mgr;
});

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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/database/daos/note_operations_dao.dart';
import 'package:supanotes/core/notifications/local_notification_service.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/data/auth_repository.dart';
import 'package:supanotes/features/auth/presentation/controllers/auth_controller.dart';
import 'package:supanotes/features/auth/domain/user.dart';
import 'package:supanotes/features/notes/data/note_operations_api.dart';

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
// Local notification service
// ---------------------------------------------------------------------------

final localNotificationServiceProvider =
    Provider<LocalNotificationService>((ref) {
  return LocalNotificationService();
});

// ---------------------------------------------------------------------------
// Note operations DAO
// ---------------------------------------------------------------------------

final noteOperationsDaoProvider = Provider.autoDispose<NoteOperationsDao>((ref) {
  return ref.watch(appDatabaseProvider).noteOperationsDao;
});

// ---------------------------------------------------------------------------
// Note operations API client
// ---------------------------------------------------------------------------

final noteOperationsApiClientProvider = Provider.autoDispose<NoteOperationsApiClient>(
  (ref) {
    return NoteOperationsApiClient(client: ref.watch(apiClientProvider));
  },
);

// ---------------------------------------------------------------------------
// Note operations sync service
// ---------------------------------------------------------------------------

final noteOperationsSyncServiceProvider =
    Provider.autoDispose<NoteOperationsSyncService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  String clientId = prefs.getString('note_ops_client_id') ?? '';
  if (clientId.isEmpty) {
    clientId = const Uuid().v4();
    prefs.setString('note_ops_client_id', clientId);
  }
  return NoteOperationsSyncService(
    api: ref.watch(noteOperationsApiClientProvider),
    dao: ref.watch(noteOperationsDaoProvider),
    clientId: clientId,
    actorId: ref.watch(currentUserIdProvider)!,
  );
});



// ---------------------------------------------------------------------------
// Shared preferences
// ---------------------------------------------------------------------------

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

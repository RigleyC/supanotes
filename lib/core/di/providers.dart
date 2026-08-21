/// Central dependency injection wiring for the SupaNotes app.
///
/// All Riverpod providers that form the DI graph are defined here so
/// there is a single, acyclic source of truth for "what depends on what".
///
/// Feature code should import this file to access providers rather than
/// declaring them inline within feature modules.
library;

import 'dart:async';

import 'package:dio/dio.dart' show Dio;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/auth_interceptor.dart' show AuthInterceptor;
import 'package:supanotes/core/auth/auth_session_resource_registry.dart';
import 'package:supanotes/core/auth/auth_token_manager.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/daos/note_operations_dao.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/notifications/local_notification_service.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/data/auth_repository.dart';
import 'package:supanotes/features/auth/domain/user.dart';
import 'package:supanotes/features/auth/presentation/controllers/auth_controller.dart';
import 'package:supanotes/features/notes/catalog/data/local/note_lifecycle_store.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_session.dart';
import 'package:supanotes/features/notes/editor/sync/note_session_activity_tracker.dart';
import 'package:supanotes/features/notes/editor/sync/note_session_coordinator.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';
import 'package:supanotes/features/notes/share/application/native_share_bridge.dart';
import 'package:supanotes/features/notes/share/application/share_intake_coordinator.dart';
import 'package:supanotes/features/notes/share/application/shared_link_delivery.dart';
import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------------
// API client
// ---------------------------------------------------------------------------

/// Single [ApiClient] with the auth interceptor wired in.
///
/// The [ApiClient] creates the [AuthInterceptor] internally and uses its
/// own [Dio] instance for refresh + replay calls. The interceptor's path
/// and retry guards prevent recursion — no separate raw Dio needed.
final apiClientProvider = Provider<ApiClient>((ref) {
  final tokens = ref.watch(authTokenManagerProvider);
  return ApiClient(
    getAccessToken: tokens.getAccessToken,
    refreshSession: tokens.refresh,
    onAuthFailure: () async {
      await ref.read(authControllerProvider.notifier).onSessionExpired();
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
    tokenManager: ref.watch(authTokenManagerProvider),
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

final nativeShareBridgeProvider = Provider<NativeShareBridge>((ref) {
  return MethodChannelNativeShareBridge();
});

final sharedLinkDeliveryProvider = Provider<SharedLinkDelivery>((ref) {
  return SharedLinkDelivery(ref.watch(apiClientProvider));
});

/// App-lifetime coordinator for native share intake (index publishing,
/// credential sync and pending-share delivery). Kept alive like [syncService]
/// because it serializes side effects across the whole app lifecycle.
final shareIntakeCoordinatorProvider = Provider<ShareIntakeCoordinator>((ref) {
  return ShareIntakeCoordinator(ref);
});

// ---------------------------------------------------------------------------
// Local notification service
// ---------------------------------------------------------------------------

final localNotificationServiceProvider = Provider<LocalNotificationService>((
  ref,
) {
  return LocalNotificationService();
});

// ---------------------------------------------------------------------------
// Note operations DAO
// ---------------------------------------------------------------------------

final noteOperationsDaoProvider = Provider<NoteOperationsDao>((ref) {
  return ref.watch(appDatabaseProvider).noteOperationsDao;
});

final Provider<NoteLifecycleStore> noteLifecycleStoreProvider = Provider.autoDispose<NoteLifecycleStore>(
  (ref) => DatabaseNoteLifecycleStore(ref.watch(appDatabaseProvider)),
);

// ---------------------------------------------------------------------------
// Note sync client
// ---------------------------------------------------------------------------

final noteSyncClientProvider = Provider<NoteSyncClient>((ref) {
  return NoteSyncClient(client: ref.watch(apiClientProvider));
});

// ---------------------------------------------------------------------------
// Note operations sync service
// ---------------------------------------------------------------------------

final noteOperationsSyncServiceProvider = Provider<NoteOperationsSyncService>((
  ref,
) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null || userId.isEmpty) {
    throw StateError(
      'NoteOperationsSyncService requires an authenticated user',
    );
  }

  final prefs = ref.watch(sharedPreferencesProvider);
  var clientId = prefs.getString('note_ops_client_id') ?? '';
  if (clientId.isEmpty) {
    clientId = const Uuid().v4();
    prefs.setString('note_ops_client_id', clientId);
  }
  return NoteOperationsSyncService(
    syncClient: ref.watch(noteSyncClientProvider),
    dao: ref.watch(noteOperationsDaoProvider),
    clientId: clientId,
    actorId: userId,
  );
});

// ---------------------------------------------------------------------------
// Note session coordinator
// ---------------------------------------------------------------------------

final noteSessionCoordinatorProvider =
    Provider<NoteSessionCoordinator<NoteEditorSession>>((ref) {
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null || userId.isEmpty) {
        throw StateError(
          'NoteSessionCoordinator requires an authenticated user',
        );
      }

      final coordinator = NoteSessionCoordinator<NoteEditorSession>(
        activityTracker: ref.watch(noteSessionActivityTrackerProvider),
      );
      final unregister = ref
          .read(authSessionResourceRegistryProvider)
          .register(coordinator.closeAll);
      ref.onDispose(() {
        unregister();
        unawaited(coordinator.closeAll());
      });
      return coordinator;
    });

final noteSessionActivityTrackerProvider = Provider<NoteSessionActivityTracker>(
  (ref) {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null || userId.isEmpty) {
      throw StateError(
        'NoteSessionActivityTracker requires an authenticated user',
      );
    }
    return NoteSessionActivityTracker();
  },
);

// ---------------------------------------------------------------------------
// Shared preferences
// ---------------------------------------------------------------------------

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

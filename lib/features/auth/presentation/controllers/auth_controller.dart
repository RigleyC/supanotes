library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/auth/auth_session_resource_registry.dart';
import 'package:supanotes/core/auth/auth_token_manager.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/data/auth_repository.dart';
import 'package:supanotes/features/auth/data/session_cache.dart';
import 'package:supanotes/features/auth/domain/user.dart';

class AuthController extends AsyncNotifier<User?> {
  late final IAuthRepository _repository;
  late final AuthLocalStorage _storage;
  late final AuthTokenManager _tokenManager;
  late final SessionCacheNotifier _sessionCache;

  @override
  Future<User?> build() async {
    _repository = ref.read(authRepositoryProvider);
    _storage = ref.read(authLocalStorageProvider);
    _tokenManager = ref.read(authTokenManagerProvider);
    _sessionCache = ref.read(sessionCacheProvider.notifier);

    await _sessionCache.restore();
    final accessToken = await _tokenManager.getAccessToken();
    if (accessToken == null || accessToken.isEmpty) return null;

    final user = await _storage.getUser();
    if (user == null) {
      await _tokenManager.clearSession();
      _sessionCache.clear();
      return null;
    }

    return user;
  }

  Future<AuthResult> _authenticate(
    Future<AuthResult> Function() attempt,
  ) async {
    state = const AsyncValue.loading();
    try {
      final result = await attempt();
      await _sessionCache.hydrate({'settings': result.session.settings});
      state = AsyncValue.data(result.user);
      return result;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<AuthResult> login({required String email, required String password}) =>
      _authenticate(() => _repository.login(email: email, password: password));

  Future<AuthResult> register({
    required String email,
    required String password,
    required String name,
  }) => _authenticate(
    () => _repository.register(email: email, password: password, name: name),
  );

  Future<void> _clearSession({required bool clearLocalData}) async {
    Object? cleanupError;
    StackTrace? cleanupStack;
    try {
      await _closeActiveSessionResources();
    } catch (error, stack) {
      cleanupError = error;
      cleanupStack = stack;
    }
    await _tokenManager.clearSession();
    _sessionCache.clear();

    if (clearLocalData) {
      // Clear last synced time to force a full pull next time
      try {
        final prefs = ref.read(sharedPreferencesProvider);
        await prefs.remove('last_synced_at');
      } catch (e) {
        debugPrint('Error clearing last_synced_at: $e');
      }

      // Explicit logout is the user-confirmed data-clearing operation.
      try {
        await ref.read(appDatabaseProvider).clearAllData();
      } catch (e) {
        debugPrint('Error clearing local database: $e');
      }
    }

    // Note: lastRouteStore is intentionally NOT cleared here.
    // The route is UX metadata, not security-sensitive data — authGuard already
    // blocks unauthenticated access to protected routes. Preserving the route
    // across involuntary session expiry lets the user land back where they were
    // after re-login. See: logout() for the explicit-logout path.
    if (cleanupError != null) {
      state = AsyncValue.error(cleanupError, cleanupStack!);
    } else {
      state = const AsyncValue.data(null);
    }
  }

  Future<void> _closeActiveSessionResources() =>
      ref.read(authSessionResourceRegistryProvider).closeAll();

  Future<void> logout() async {
    state = const AsyncValue.loading();
    try {
      await _repository.logout();
    } catch (e) {
      debugPrint('logout error: $e');
    }
    await _clearSession(clearLocalData: true);

    ref.read(sessionResetProvider.notifier).update((state) => state + 1);
  }

  /// Called by the [AuthInterceptor] when a refresh has failed.
  Future<void> onSessionExpired() async {
    // Keep local notes and the outbox. A failed refresh must not destroy
    // changes that have not reached the server yet.
    await _clearSession(clearLocalData: false);
    ref.read(sessionResetProvider.notifier).update((state) => state + 1);
  }
}

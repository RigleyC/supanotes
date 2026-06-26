library;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/router/last_route_store.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/data/auth_repository.dart';
import 'package:supanotes/features/auth/data/session_cache.dart';
import 'package:supanotes/features/auth/domain/user.dart';

class AuthController extends AsyncNotifier<User?> {
  late final IAuthRepository _repository;
  late final AuthLocalStorage _storage;
  late final SessionCacheNotifier _sessionCache;

  @override
  Future<User?> build() async {
    _repository = ref.read(authRepositoryProvider);
    _storage = ref.read(authLocalStorageProvider);
    _sessionCache = ref.read(sessionCacheProvider.notifier);

    await _sessionCache.restore();
    final accessToken = await _storage.getAccessToken();
    if (accessToken == null || accessToken.isEmpty) return null;

    final user = await _storage.getUser();
    if (user == null) {
      await _storage.clear();
      _sessionCache.clear();
      return null;
    }

    await _registerFcmToken();
    return user;
  }

  Future<void> _registerFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _repository.registerDeviceToken(token);
      }
    } catch (e) {
      debugPrint('push notification registration failed: $e');
    }
  }

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    state = const AsyncValue.loading();
    try {
      final result = await _repository.login(email: email, password: password);
      await _sessionCache.hydrate({
        'settings': result.session.settings,
        'soul': result.session.soul,
        'contexts': result.session.contexts,
        'routines': result.session.routines,
      });
      state = AsyncValue.data(result.user);
      await _registerFcmToken();
      return result;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<AuthResult> register({
    required String email,
    required String password,
    required String name,
  }) async {
    state = const AsyncValue.loading();
    try {
      final result = await _repository.register(
        email: email,
        password: password,
        name: name,
      );
      await _sessionCache.hydrate({
        'settings': result.session.settings,
        'soul': result.session.soul,
        'contexts': result.session.contexts,
        'routines': result.session.routines,
      });
      state = AsyncValue.data(result.user);
      await _registerFcmToken();
      return result;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> _clearSession() async {
    await _storage.clear();
    _sessionCache.clear();
    // Note: lastRouteStore is intentionally NOT cleared here.
    // The route is UX metadata, not security-sensitive data — authGuard already
    // blocks unauthenticated access to protected routes. Preserving the route
    // across involuntary session expiry lets the user land back where they were
    // after re-login. See: logout() for the explicit-logout path.
    state = const AsyncValue.data(null);
  }

  Future<void> logout() async {
    state = const AsyncValue.loading();
    try {
      await _repository.logout();
    } catch (e) {
      debugPrint('logout error: $e');
    }
    // On explicit logout, clear the saved route so the user starts fresh.
    await ref.read(lastRouteStoreProvider).clear();
    await _clearSession();
  }

  /// Called by the [AuthInterceptor] when a refresh has failed.
  Future<void> onSessionExpired() async {
    await _clearSession();
  }
}

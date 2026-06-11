library;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/data/auth_repository.dart';
import 'package:supanotes/features/auth/data/session_cache.dart';
import 'package:supanotes/features/auth/domain/user.dart';

class AuthController extends Notifier<AsyncValue<User?>> {
  late final IAuthRepository _repository;
  late final AuthLocalStorage _storage;
  late final SessionCacheNotifier _sessionCache;

  @override
  AsyncValue<User?> build() {
    _repository = ref.read(authRepositoryProvider);
    _storage = ref.read(authLocalStorageProvider);
    _sessionCache = ref.read(sessionCacheProvider.notifier);
    Future.microtask(_restore);
    return const AsyncValue.loading();
  }

  Future<void> _restore() async {
    await _sessionCache.restore();
    final results = await Future.wait([
      _storage.getAccessToken(),
      _storage.getUserId(),
      _storage.getUserEmail(),
      _storage.getUserName(),
    ]);
    final accessToken = results[0];
    if (accessToken == null || accessToken.isEmpty) {
      state = const AsyncValue.data(null);
      return;
    }
    final userId = results[1];
    final email = results[2];
    final name = results[3];
    if (userId == null || email == null || name == null) {
      await _storage.clear();
      _sessionCache.clear();
      state = const AsyncValue.data(null);
      return;
    }
    state = AsyncValue.data(User(id: userId, email: email, name: name));
    await _registerFcmToken();
  }

  Future<void> _registerFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _repository.registerDeviceToken(token);
      }
    } catch (_) {
      // Non-fatal: push notifications may not work.
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

  Future<void> logout() async {
    state = const AsyncValue.loading();
    try {
      await _repository.logout();
    } catch (_) {
      // Network errors during logout are non-fatal — the local session
      // is still cleared on the next line.
    }
    await _storage.clear();
    _sessionCache.clear();
    state = const AsyncValue.data(null);
  }

  /// Called by the [AuthInterceptor] when a refresh has failed.
  Future<void> onSessionExpired() async {
    await _storage.clear();
    _sessionCache.clear();
    state = const AsyncValue.data(null);
  }
}

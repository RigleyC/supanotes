/// Riverpod [AsyncNotifier] that owns the global [AuthState].
///
/// Responsibilities:
///   * `build()` — on cold start, inspect the secure storage and emit
///     [AuthAuthenticated] (if a full session is on disk) or
///     [AuthUnauthenticated]. While `build()` is running the provider's
///     state is [AsyncLoading], which the router treats as "do not
///     redirect yet".
///   * `login` / `register` — call the [AuthRepository] and emit
///     [AuthAuthenticated] on success, or rethrow the [ApiException] so
///     the calling widget can show a snackbar.
///   * `logout` — call the [AuthRepository], always end up in
///     [AuthUnauthenticated] regardless of the network outcome.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/data/auth_repository.dart';
import 'package:supanotes/features/auth/domain/auth_state.dart';
import 'package:supanotes/features/auth/domain/user.dart';

class AuthController extends AsyncNotifier<AuthState> {
  late final AuthRepository _repository;
  late final AuthLocalStorage _storage;

  @override
  Future<AuthState> build() async {
    _repository = ref.read(authRepositoryProvider);
    _storage = ref.read(authLocalStorageProvider);
    return _restore();
  }

  Future<AuthState> _restore() async {
    final accessToken = await _storage.getAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      return const AuthUnauthenticated();
    }
    final userId = await _storage.getUserId();
    final email = await _storage.getUserEmail();
    final name = await _storage.getUserName();
    if (userId == null || email == null || name == null) {
      // Partial session — wipe and force a re-login.
      await _storage.clear();
      return const AuthUnauthenticated();
    }
    return AuthAuthenticated(userId: userId, email: email, name: name);
  }

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    state = const AsyncValue<AuthState>.loading();
    try {
      final result = await _repository.login(email: email, password: password);
      state = AsyncValue.data(
        AuthAuthenticated(
          userId: result.user.id,
          email: result.user.email,
          name: result.user.name,
        ),
      );
      return result;
    } catch (e, st) {
      state = AsyncValue<AuthState>.error(e, st);
      rethrow;
    }
  }

  Future<AuthResult> register({
    required String email,
    required String password,
    required String name,
  }) async {
    state = const AsyncValue<AuthState>.loading();
    try {
      final result = await _repository.register(
        email: email,
        password: password,
        name: name,
      );
      state = AsyncValue.data(
        AuthAuthenticated(
          userId: result.user.id,
          email: result.user.email,
          name: result.user.name,
        ),
      );
      return result;
    } catch (e, st) {
      state = AsyncValue<AuthState>.error(e, st);
      rethrow;
    }
  }

  Future<void> logout() async {
    state = const AsyncValue<AuthState>.loading();
    try {
      await _repository.logout();
    } on ApiException {
      // Swallow: the local state must end up unauthenticated regardless.
    } finally {
      state = const AsyncValue<AuthState>.data(AuthUnauthenticated());
    }
  }

  /// Called by the [AuthInterceptor] when a refresh has failed.
  ///
  /// We don't call the network here — the interceptor already knows the
  /// refresh is dead. We just need to flip the state so the router can
  /// redirect to /login.
  Future<void> onSessionExpired() async {
    await _storage.clear();
    state = const AsyncValue<AuthState>.data(AuthUnauthenticated());
  }
}

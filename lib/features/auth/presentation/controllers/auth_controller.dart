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
  late final IAuthRepository _repository;
  late final AuthLocalStorage _storage;

  @override
  Future<AuthState> build() async {
    _repository = ref.read(authRepositoryProvider);
    _storage = ref.read(authLocalStorageProvider);
    return _restore();
  }

  Future<AuthState> _restore() async {
    final results = await Future.wait([
      _storage.getAccessToken(),
      _storage.getUserId(),
      _storage.getUserEmail(),
      _storage.getUserName(),
    ]);
    final accessToken = results[0] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      return const AuthUnauthenticated();
    }
    final userId = results[1] as String?;
    final email = results[2] as String?;
    final name = results[3] as String?;
    if (userId == null || email == null || name == null) {
      await _storage.clear();
      return const AuthUnauthenticated();
    }
    return AuthAuthenticated(User(id: userId, email: email, name: name));
  }

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    state = const AsyncValue<AuthState>.loading();
    try {
      final result = await _repository.login(email: email, password: password);
      state = AsyncValue.data(
        AuthAuthenticated(result.user),
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
        AuthAuthenticated(result.user),
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
    } catch (_) {
      // Network errors during logout are non-fatal — the local session
      // is still cleared on the next line.
    }
    state = const AsyncValue<AuthState>.data(AuthUnauthenticated());
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

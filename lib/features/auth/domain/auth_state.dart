/// Auth state machine and the Riverpod controller that drives it.
///
/// This file is intentionally self-contained: it owns the state hierarchy,
/// the [AuthController] class, and the three auth-related providers
/// ([authLocalStorageProvider], [authRepositoryProvider],
/// [authControllerProvider]). The DI module in `core/di/providers.dart`
/// re-exports them so the rest of the app can import from a single
/// location.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/data/auth_repository.dart';
import 'package:supanotes/features/auth/domain/user.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// State machine for the current auth session.
///
/// Exposed as a [sealed class] so consumers can exhaustively pattern-match
/// on the three legitimate states (initial / unauthenticated / authenticated)
/// without worrying about a fourth "loading" shape — that concern is owned
/// by Riverpod's [AsyncValue] wrapper around this state.
sealed class AuthState {
  const AuthState();
}

/// The auth provider has not yet checked local storage.
///
/// Rendered briefly at app start; the router does not redirect while
/// this is the current state so we don't bounce the user to /login before
/// we know whether they have a saved session.
class AuthInitial extends AuthState {
  const AuthInitial();
}

/// The device has no session (or the session was just revoked by a
/// failed refresh). The router should bounce the user to /login.
class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

/// The device has a valid session and we know the user's id, email, and
/// display name. These are all read from the backend response on login /
/// register; the controller does not currently re-fetch the profile.
class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({
    required this.userId,
    required this.email,
    required this.name,
  });

  final String userId;
  final String email;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is AuthAuthenticated &&
      other.userId == userId &&
      other.email == email &&
      other.name == name;

  @override
  int get hashCode => Object.hash(userId, email, name);
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Singleton [AuthLocalStorage] for the lifetime of the app.
final authLocalStorageProvider = Provider<AuthLocalStorage>((ref) {
  return AuthLocalStorage();
});

/// Single [AuthRepository] wired to the shared [apiClientProvider].
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    apiClient: ref.watch(apiClientProvider),
    storage: ref.watch(authLocalStorageProvider),
  );
});

/// Global [AuthController] — consumed by the router, the auth screens,
/// and any other widget that needs to know the current session.
final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);

// ---------------------------------------------------------------------------
// Forward declaration
// ---------------------------------------------------------------------------

/// The real [apiClientProvider] is defined in `core/di/providers.dart`
/// alongside the rest of the DI graph. We can't import that file from
/// here (it would be a cycle: the DI module declares
/// [authControllerProvider], which references [AuthController] from this
/// file). Instead, [core/di/providers.dart] does
/// `apiClientProvider = Provider<ApiClient>(...)` and this `late final`
/// picks up the value at first read.
///
/// The boot order is: the DI module is loaded first, which assigns to
/// [apiClientProvider]; only then does [authRepositoryProvider] get
/// materialised, triggering the [apiClientProvider] read.
late final Provider<ApiClient> apiClientProvider;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/auth/auth_session_resource_registry.dart';
import 'package:supanotes/core/auth/auth_token_manager.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/sync/sync_inbox_store.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/data/auth_repository.dart';
import 'package:supanotes/features/auth/data/session_cache.dart';
import 'package:supanotes/features/auth/domain/user.dart';

class AuthController extends AsyncNotifier<User?> {
  late final AuthRepository _repository;
  late final AuthLocalStorage _storage;
  late final AuthTokenManager _tokenManager;
  late final SessionCacheNotifier _sessionCache;
  late final AuthSessionCleanup _sessionCleanup;
  Future<void> _operationTail = Future<void>.value();

  @override
  Future<User?> build() async {
    _repository = ref.read(authRepositoryProvider);
    _storage = ref.read(authLocalStorageProvider);
    _tokenManager = ref.read(authTokenManagerProvider);
    _sessionCache = ref.read(sessionCacheProvider.notifier);
    final preferences = ref.read(sharedPreferencesProvider);
    final database = ref.read(appDatabaseProvider);
    _sessionCleanup = AuthSessionCleanup(
      closeResources: ref.read(authSessionResourceRegistryProvider).closeAll,
      invalidateCredentials: _tokenManager.clearSession,
      clearCache: _sessionCache.clear,
      clearPreferences: () => preferences.remove('last_synced_at'),
      clearInbox: () => SyncInboxStore(database).clearAll(),
      clearDatabase: database.clearAllData,
    );

    await _sessionCache.restore();
    final hasCompleteSession = await _tokenManager.hasCompleteSession();
    if (!hasCompleteSession) {
      final accessToken = await _tokenManager.getAccessToken();
      final refreshToken = await _tokenManager.getRefreshToken();
      final user = await _storage.getUser();
      if (_hasValue(accessToken) || _hasValue(refreshToken) || user != null) {
        await _tokenManager.clearSession();
      }
      _sessionCache.clear();
      return null;
    }

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
  ) {
    return ref.read(authActionProvider.notifier).run(() async {
      try {
        final result = await attempt();
        await _sessionCache.hydrate({'settings': result.session.settings});
        state = AsyncValue.data(result.user);
        return result;
      } on AuthSessionInstallationException {
        _sessionCache.clear();
        state = const AsyncValue.data(null);
        rethrow;
      }
    });
  }

  Future<AuthResult> login({required String email, required String password}) =>
      _serialize(
        () => _authenticate(
          () => _repository.login(email: email, password: password),
        ),
      );

  Future<AuthResult> register({
    required String email,
    required String password,
    required String name,
  }) => _serialize(
    () => _authenticate(
      () => _repository.register(email: email, password: password, name: name),
    ),
  );

  Future<void> _clearSession({required bool clearLocalData}) async {
    final report = await _sessionCleanup.run(clearLocalData: clearLocalData);

    // Note: lastRouteStore is intentionally NOT cleared here.
    // The route is UX metadata, not security-sensitive data — authGuard already
    // blocks unauthenticated access to protected routes. Preserving the route
    // across involuntary session expiry lets the user land back where they were
    // after re-login. See: logout() for the explicit-logout path.
    if (report.error != null) {
      state = AsyncValue.error(report.error!, report.stackTrace!);
    } else {
      state = const AsyncValue.data(null);
    }
  }

  Future<void> logout() => _serialize(
    () => ref.read(authActionProvider.notifier).run(() async {
      try {
        await _repository.logout();
      } catch (e) {
        debugPrint('logout error: $e');
      }
      await _clearSession(clearLocalData: true);
    }),
  );

  /// Called by the auth interceptor when a refresh has failed.
  Future<void> onSessionExpired() => _serialize(() async {
    // Keep local notes and the outbox. A failed refresh must not destroy
    // changes that have not reached the server yet.
    await _clearSession(clearLocalData: false);
  });

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final previous = _operationTail;
    final release = Completer<void>();
    _operationTail = release.future;
    return previous.then((_) async {
      try {
        return await operation();
      } finally {
        release.complete();
      }
    });
  }

  static bool _hasValue(String? value) => value != null && value.isNotEmpty;
}

typedef AuthSessionCleanupAction = FutureOr<void> Function();

final class AuthSessionCleanup {
  const AuthSessionCleanup({
    required this.closeResources,
    required this.invalidateCredentials,
    required this.clearCache,
    required this.clearPreferences,
    required this.clearInbox,
    required this.clearDatabase,
  });

  final AuthSessionCleanupAction closeResources;
  final AuthSessionCleanupAction invalidateCredentials;
  final AuthSessionCleanupAction clearCache;
  final AuthSessionCleanupAction clearPreferences;
  final AuthSessionCleanupAction clearInbox;
  final AuthSessionCleanupAction clearDatabase;

  Future<SessionCleanupReport> run({required bool clearLocalData}) async {
    final failures = <SessionCleanupFailure>[];
    await _runStep('resources', closeResources, failures);
    await _runStep('credentials', invalidateCredentials, failures);
    await _runStep('cache', clearCache, failures);
    if (clearLocalData) {
      await _runStep('preferences', clearPreferences, failures);
      await _runStep('inbox', clearInbox, failures);
      await _runStep('database', clearDatabase, failures);
    }
    return SessionCleanupReport(failures);
  }

  static Future<void> _runStep(
    String step,
    AuthSessionCleanupAction action,
    List<SessionCleanupFailure> failures,
  ) async {
    try {
      await action();
    } catch (error, stackTrace) {
      failures.add(
        SessionCleanupFailure(
          step: step,
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}

final class SessionCleanupFailure {
  const SessionCleanupFailure({
    required this.step,
    required this.error,
    required this.stackTrace,
  });

  final String step;
  final Object error;
  final StackTrace stackTrace;
}

final class SessionCleanupReport {
  SessionCleanupReport(List<SessionCleanupFailure> failures)
    : failures = List.unmodifiable(failures);

  final List<SessionCleanupFailure> failures;

  Object? get error {
    if (failures.isEmpty) return null;
    if (failures.length == 1) return failures.single.error;
    return SessionCleanupException(failures);
  }

  StackTrace? get stackTrace =>
      failures.isEmpty ? null : failures.first.stackTrace;
}

final class SessionCleanupException implements Exception {
  const SessionCleanupException(this.failures);

  final List<SessionCleanupFailure> failures;

  @override
  String toString() {
    final details = failures
        .map((failure) => '${failure.step}: ${failure.error}')
        .join('; ');
    return 'Session cleanup failed: $details';
  }
}

/// Reports authentication action progress independently from the current
/// session identity. A failed login therefore cannot turn an existing valid
/// session into an authentication error state.
class AuthActionController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<T> run<T>(Future<T> Function() operation) async {
    state = const AsyncValue.loading();
    try {
      final result = await operation();
      state = const AsyncValue.data(null);
      return result;
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    }
  }
}

final authActionProvider =
    AsyncNotifierProvider.autoDispose<AuthActionController, void>(
      AuthActionController.new,
    );

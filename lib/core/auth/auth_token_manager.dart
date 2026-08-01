import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/auth_interceptor.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';

/// Owns the active access token and its secure persisted token pair.
///
/// The access token is read from memory after the first load. Explicit session
/// operations keep the interceptor cache and secure storage in sync.
class AuthTokenManager {
  AuthTokenManager({required AuthLocalStorage storage}) : _storage = storage;

  final AuthLocalStorage _storage;

  String? _accessToken;
  bool _loaded = false;
  bool _sessionCleared = false;
  Future<void>? _clearInFlight;

  Future<String?> getAccessToken() async {
    if (!_loaded) {
      _accessToken = await _storage.getAccessToken();
      _loaded = true;
    }
    return _accessToken;
  }

  Future<String?> getRefreshToken() => _storage.getRefreshToken();

  /// Serializes a refresh request with credential replacement and cleanup.
  Future<AuthTokenPair?> refresh(RefreshHandler perform) =>
      _exclusive(() async {
        final refreshToken = await _storage.getRefreshToken();
        if (refreshToken == null) return null;

        final tokens = await perform(refreshToken);
        if (tokens == null) return null;

        await _installSession(tokens);
        return tokens;
      });

  /// Installs credentials returned by login or registration.
  Future<void> installSession({
    required String accessToken,
    required String refreshToken,
  }) => _exclusive(
    () =>
        _installSession((accessToken: accessToken, refreshToken: refreshToken)),
  );

  Future<void> _installSession(AuthTokenPair tokens) async {
    await _storage.saveTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
    _accessToken = tokens.accessToken;
    _loaded = true;
    _sessionCleared = false;
  }

  /// Replaces credentials returned by a refresh operation.
  Future<void> replaceTokens({
    required String accessToken,
    required String refreshToken,
  }) => installSession(accessToken: accessToken, refreshToken: refreshToken);

  /// Clears the active credentials and all persisted session data.
  Future<void> clearSession() {
    final inFlight = _clearInFlight;
    if (inFlight != null) return inFlight;
    if (_sessionCleared) return Future<void>.value();

    _accessToken = null;
    _loaded = true;
    _sessionCleared = true;
    late final Future<void> clear;
    clear =
        _exclusive(() async {
          _accessToken = null;
          try {
            await _storage.clear();
          } catch (_) {
            _sessionCleared = false;
            rethrow;
          }
        }).whenComplete(() {
          if (identical(_clearInFlight, clear)) {
            _clearInFlight = null;
          }
        });
    _clearInFlight = clear;
    return clear;
  }

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    return previous.then((_) async {
      try {
        return await operation();
      } finally {
        release.complete();
      }
    });
  }

  Future<void> _tail = Future<void>.value();
}

final authTokenManagerProvider = Provider<AuthTokenManager>((ref) {
  return AuthTokenManager(storage: ref.watch(authLocalStorageProvider));
});

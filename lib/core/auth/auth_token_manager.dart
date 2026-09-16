import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/auth/auth_tokens.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';

/// Owns the active access token and its secure persisted token pair.
///
/// The access token is read from memory after the first load. Explicit session
/// operations keep the interceptor cache and secure storage in sync.
class AuthTokenManager {
  /// Creates a manager backed by the app's secure local storage.
  AuthTokenManager({required AuthLocalStorage storage}) : _storage = storage;

  final AuthLocalStorage _storage;

  AuthTokenState? _tokenState;
  bool _stateLoaded = false;
  bool _sessionCleared = false;
  Future<void>? _clearInFlight;
  Future<AuthTokenState?>? _loadInFlight;
  int _sessionGeneration = 0;

  /// Returns the current access token, if one is present.
  Future<String?> getAccessToken() async {
    final state = await _loadState();
    return _hasValue(state?.accessToken) ? state!.accessToken : null;
  }

  /// Reads the refresh token after any in-flight install, refresh or cleanup.
  ///
  /// Logout uses this boundary before calling the server. Without the
  /// serialization, logout could send the parent token while a refresh was
  /// already rotating it, leaving the server and local session out of order.
  Future<String?> getRefreshToken() => _exclusive(() async {
    return (await _loadState())?.refreshToken;
  });

  /// Runs an operation while the refresh token and its credential replacement
  /// are serialized. Logout uses this boundary to keep its server call paired
  /// with the token it read.
  Future<T> withSessionLock<T>(
    Future<T> Function(String? refreshToken) operation,
  ) => _exclusive(() async {
    return operation((await _loadState())?.refreshToken);
  });

  /// A session is usable only when both sides of the credential pair exist.
  Future<bool> hasCompleteSession() async {
    final state = await _loadState();
    return _hasValue(state?.accessToken) && _hasValue(state?.refreshToken);
  }

  /// Serializes a refresh request with credential replacement and cleanup.
  Future<AuthTokenPair?> refresh(RefreshHandler perform) =>
      _exclusive(() async {
        final refreshToken = (await _loadState())?.refreshToken;
        if (refreshToken == null || refreshToken.isEmpty) return null;

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
    if (!_hasValue(tokens.accessToken) || !_hasValue(tokens.refreshToken)) {
      throw ArgumentError('Both authentication tokens are required');
    }

    await _storage.saveTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
    _tokenState = tokens;
    _stateLoaded = true;
    _sessionCleared = false;
    _sessionGeneration++;
  }

  /// Clears the active credentials and all persisted session data.
  Future<void> clearSession() {
    final inFlight = _clearInFlight;
    if (inFlight != null) return inFlight;
    if (_sessionCleared) return Future<void>.value();

    _tokenState = null;
    _stateLoaded = true;
    _sessionCleared = true;
    _sessionGeneration++;
    late final Future<void> clear;
    clear =
        _exclusive(() async {
          _tokenState = null;
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

  Future<AuthTokenState?> _loadState() async {
    if (_stateLoaded) return _tokenState;
    final cached = _loadInFlight;
    if (cached != null) return cached;

    final generation = _sessionGeneration;
    late final Future<AuthTokenState?> load;
    load =
        Future.wait<String?>([
              _storage.getAccessToken(),
              _storage.getRefreshToken(),
            ])
            .then((tokens) {
              final accessToken = tokens[0];
              final refreshToken = tokens[1];
              final state = (
                accessToken: accessToken,
                refreshToken: refreshToken,
              );
              if (!_stateLoaded && generation == _sessionGeneration) {
                _tokenState = state;
                _stateLoaded = true;
              }
              return _tokenState;
            })
            .whenComplete(() {
              if (identical(_loadInFlight, load)) _loadInFlight = null;
            });
    _loadInFlight = load;
    return load;
  }

  static bool _hasValue(String? value) => value != null && value.isNotEmpty;
}

/// Provides the app-wide authentication token manager.
final authTokenManagerProvider = Provider<AuthTokenManager>((ref) {
  return AuthTokenManager(storage: ref.watch(authLocalStorageProvider));
});

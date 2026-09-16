/// Secure, on-device persistence of the JWT pair, the current user, and the
/// cached session bootstrap (settings, soul, contexts, routines).
///
/// Backed by [FlutterSecureStorage] which on Android uses the
/// EncryptedSharedPreferences keystore and on iOS uses the Keychain. The
/// platform layer requires no additional configuration in dev — the tokens
/// are wiped when the app is uninstalled, which is the desired behaviour
/// for a session-scoped secret.
///
/// All keys are kept private to this file so a typo in a calling site
/// cannot quietly write to a different namespace.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supanotes/core/auth/auth_tokens.dart';
import 'package:supanotes/features/auth/domain/user.dart';

class AuthLocalStorage {
  AuthLocalStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _kAccessToken = 'access_token';
  static const String _kRefreshToken = 'refresh_token';
  static const String _kTokenPair = 'auth_token_pair';
  static const String _kUser = 'user';
  static const String _kSessionData = 'session_data';

  Future<_TokenPairRecord>? _tokenPairRead;

  /// Persists the JWT pair as one record. The user profile is not touched;
  /// call [saveUser] separately when the authenticated user changes.
  ///
  /// Legacy keys are removed only after the pair has been written, so an
  /// interrupted migration cannot pair a new access token with an old refresh
  /// token.
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    if (accessToken.isEmpty || refreshToken.isEmpty) {
      throw ArgumentError('Both authentication tokens are required');
    }

    final tokens = (accessToken: accessToken, refreshToken: refreshToken);
    late final Future<_TokenPairRecord> write;
    write = () async {
      await _storage.write(
        key: _kTokenPair,
        value: jsonEncode({
          _kAccessToken: accessToken,
          _kRefreshToken: refreshToken,
        }),
      );
      await Future.wait<dynamic>([
        _storage.delete(key: _kAccessToken),
        _storage.delete(key: _kRefreshToken),
      ]);
      return _TokenPairRecord.valid(tokens);
    }();
    _tokenPairRead = write;
    try {
      await write;
    } catch (_) {
      if (identical(_tokenPairRead, write)) _tokenPairRead = null;
      rethrow;
    }
  }

  /// Persists the cached profile. Called by the auth repository on a
  /// successful login or register so the session controller can restore
  /// the user on the next cold start without an extra /me call.
  Future<void> saveUser({required User user}) async {
    await _storage.write(key: _kUser, value: jsonEncode(user.toJson()));
  }

  Future<String?> getAccessToken() => _readToken(_kAccessToken);

  Future<String?> getRefreshToken() => _readToken(_kRefreshToken);

  Future<String?> _readToken(String key) async {
    final record = await _readTokenPair();
    return switch (record.status) {
      _TokenPairStatus.valid =>
        key == _kAccessToken
            ? record.tokens!.accessToken
            : record.tokens!.refreshToken,
      _TokenPairStatus.invalid => null,
      _TokenPairStatus.absent => _storage.read(key: key),
    };
  }

  Future<_TokenPairRecord> _readTokenPair() {
    final cached = _tokenPairRead;
    if (cached != null) return cached;

    late final Future<_TokenPairRecord> read;
    read = _storage.read(key: _kTokenPair).then(_parseTokenPair);
    _tokenPairRead = read;
    return read;
  }

  _TokenPairRecord _parseTokenPair(String? raw) {
    if (raw == null) return const _TokenPairRecord.absent();
    if (raw.isEmpty) return const _TokenPairRecord.invalid();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const _TokenPairRecord.invalid();
      final accessToken = decoded[_kAccessToken];
      final refreshToken = decoded[_kRefreshToken];
      if (accessToken is! String ||
          accessToken.isEmpty ||
          refreshToken is! String ||
          refreshToken.isEmpty) {
        return const _TokenPairRecord.invalid();
      }
      return _TokenPairRecord.valid(
        (accessToken: accessToken, refreshToken: refreshToken),
      );
    } catch (_) {
      debugPrint('getTokenPair decode error');
      return const _TokenPairRecord.invalid();
    }
  }

  /// Returns the cached profile, or `null` if missing or corrupt.
  Future<User?> getUser() async {
    final raw = await _storage.read(key: _kUser);
    if (raw == null || raw.isEmpty) return null;
    try {
      return User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('getUser decode error: $e');
      return null;
    }
  }

  /// Persists the raw session data (settings, soul, contexts, routines)
  /// as a JSON blob so controllers can hydrate from disk on cold start.
  Future<void> saveSessionData(Map<String, dynamic> data) async {
    await _storage.write(key: _kSessionData, value: jsonEncode(data));
  }

  /// Returns the parsed session data or an empty map if missing.
  Future<Map<String, dynamic>> getSessionData() async {
    final raw = await _storage.read(key: _kSessionData);
    if (raw == null || raw.isEmpty) return const {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('getSessionData decode error: $e');
      return const {};
    }
  }

  /// Wipes every key this class owns, including legacy token keys.
  Future<void> clear() async {
    late final Future<_TokenPairRecord> clear;
    clear = Future.wait<dynamic>([
      _storage.delete(key: _kTokenPair),
      _storage.delete(key: _kAccessToken),
      _storage.delete(key: _kRefreshToken),
      _storage.delete(key: _kUser),
      _storage.delete(key: _kSessionData),
    ]).then((_) => const _TokenPairRecord.absent());
    _tokenPairRead = clear;
    try {
      await clear;
    } catch (_) {
      if (identical(_tokenPairRead, clear)) _tokenPairRead = null;
      rethrow;
    }
  }
}

enum _TokenPairStatus { absent, invalid, valid }

final class _TokenPairRecord {
  const _TokenPairRecord.absent()
    : status = _TokenPairStatus.absent,
      tokens = null;

  const _TokenPairRecord.invalid()
    : status = _TokenPairStatus.invalid,
      tokens = null;

  const _TokenPairRecord.valid(this.tokens) : status = _TokenPairStatus.valid;

  final _TokenPairStatus status;
  final AuthTokenPair? tokens;
}

final authLocalStorageProvider = Provider<AuthLocalStorage>((ref) {
  return AuthLocalStorage();
});

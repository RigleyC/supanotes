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
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/auth/domain/user.dart';

class AuthLocalStorage {
  AuthLocalStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _kAccessToken = 'access_token';
  static const String _kRefreshToken = 'refresh_token';
  static const String _kUser = 'user';
  static const String _kSessionData = 'session_data';

  /// Persists the JWT pair. The user profile is **not** touched — call
  /// [saveUser] separately so the [AuthInterceptor] can re-save tokens on
  /// a refresh without needing the profile on hand.
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait<dynamic>([
      _storage.write(key: _kAccessToken, value: accessToken),
      _storage.write(key: _kRefreshToken, value: refreshToken),
    ]);
  }

  /// Persists the cached profile. Called by the auth repository on a
  /// successful login or register so the [AuthController] can restore
  /// the user on the next cold start without an extra /me call.
  Future<void> saveUser({required User user}) async {
    await _storage.write(key: _kUser, value: jsonEncode(user.toJson()));
  }

  Future<String?> getAccessToken() => _storage.read(key: _kAccessToken);

  Future<String?> getRefreshToken() => _storage.read(key: _kRefreshToken);

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

  /// Wipes every key this class owns.
  Future<void> clear() async {
    await Future.wait<dynamic>([
      _storage.delete(key: _kAccessToken),
      _storage.delete(key: _kRefreshToken),
      _storage.delete(key: _kUser),
      _storage.delete(key: _kSessionData),
    ]);
  }
}

final authLocalStorageProvider = Provider<AuthLocalStorage>((ref) {
  return AuthLocalStorage();
});

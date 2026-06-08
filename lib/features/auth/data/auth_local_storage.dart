/// Secure, on-device persistence of the JWT pair, the current user id,
/// and the cached profile (email, name).
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

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthLocalStorage {
  AuthLocalStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _kAccessToken = 'access_token';
  static const String _kRefreshToken = 'refresh_token';
  static const String _kUserId = 'user_id';
  static const String _kUserEmail = 'user_email';
  static const String _kUserName = 'user_name';
  static const String _kSessionData = 'session_data';

  /// Persists the JWT pair and the user id. The user profile (email/name)
  /// is **not** touched — call [saveUserProfile] separately so the
  /// [AuthInterceptor] can re-save tokens on a refresh without needing
  /// the profile on hand.
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required String userId,
  }) async {
    await Future.wait<dynamic>([
      _storage.write(key: _kAccessToken, value: accessToken),
      _storage.write(key: _kRefreshToken, value: refreshToken),
      _storage.write(key: _kUserId, value: userId),
    ]);
  }

  /// Persists the cached profile. Called by the auth repository on a
  /// successful login or register so the [AuthController] can restore
  /// [AuthAuthenticated] on the next cold start without an extra /me call.
  Future<void> saveUserProfile({
    required String email,
    required String name,
  }) async {
    await Future.wait<dynamic>([
      _storage.write(key: _kUserEmail, value: email),
      _storage.write(key: _kUserName, value: name),
    ]);
  }

  Future<String?> getAccessToken() => _storage.read(key: _kAccessToken);

  Future<String?> getRefreshToken() => _storage.read(key: _kRefreshToken);

  Future<String?> getUserId() => _storage.read(key: _kUserId);

  Future<String?> getUserEmail() => _storage.read(key: _kUserEmail);

  Future<String?> getUserName() => _storage.read(key: _kUserName);

  /// Persists the raw session data (settings, soul, contexts, routines)
  /// as a JSON blob so controllers can hydrate from disk on cold start.
  Future<void> saveSessionData(Map<String, dynamic> data) async {
    await _storage.write(
      key: _kSessionData,
      value: jsonEncode(data),
    );
  }

  /// Returns the parsed session data or an empty map if missing.
  Future<Map<String, dynamic>> getSessionData() async {
    final raw = await _storage.read(key: _kSessionData);
    if (raw == null || raw.isEmpty) return const {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  /// Wipes every key this class owns.
  Future<void> clear() async {
    await Future.wait<dynamic>([
      _storage.delete(key: _kAccessToken),
      _storage.delete(key: _kRefreshToken),
      _storage.delete(key: _kUserId),
      _storage.delete(key: _kUserEmail),
      _storage.delete(key: _kUserName),
      _storage.delete(key: _kSessionData),
    ]);
  }
}

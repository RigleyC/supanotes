/// Secure, on-device persistence of the JWT pair and the current user id.
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

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthLocalStorage {
  AuthLocalStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _kAccessToken = 'access_token';
  static const String _kRefreshToken = 'refresh_token';
  static const String _kUserId = 'user_id';

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

  Future<String?> getAccessToken() => _storage.read(key: _kAccessToken);

  Future<String?> getRefreshToken() => _storage.read(key: _kRefreshToken);

  Future<String?> getUserId() => _storage.read(key: _kUserId);

  /// Wipes every key this class owns.
  Future<void> clear() async {
    await Future.wait<dynamic>([
      _storage.delete(key: _kAccessToken),
      _storage.delete(key: _kRefreshToken),
      _storage.delete(key: _kUserId),
    ]);
  }
}

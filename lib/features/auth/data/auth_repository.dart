library;
import 'dart:io' show Platform;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/domain/user.dart';

abstract class IAuthRepository {
  Future<AuthResult> register({
    required String email,
    required String password,
    required String name,
  });
  Future<AuthResult> login({required String email, required String password});
  Future<void> logout();
  Future<bool> isAuthenticated();
  Future<void> registerDeviceToken(String token);
}

class AuthRepository implements IAuthRepository {
  AuthRepository({
    required ApiClient apiClient,
    required AuthLocalStorage storage,
  }) : _api = apiClient,
       _storage = storage;

  final ApiClient _api;
  final AuthLocalStorage _storage;

  @override
  Future<AuthResult> register({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        '/auth/register',
        data: {'email': email, 'password': password, 'name': name},
      );
      final body = response.data;
      if (body == null) {
        throw const ServerException(
          message: 'Empty response from server',
          statusCode: 500,
        );
      }
      final result = AuthResult.fromJson(body);
      await _storage.saveUser(user: result.user);
      await _storage.saveTokens(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
      );
      await _storage.saveSessionData({
        'settings': result.session.settings,
      });
      return result;
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  @override
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      final body = response.data;
      if (body == null) {
        throw const ServerException(
          message: 'Empty response from server',
          statusCode: 500,
        );
      }
      final result = AuthResult.fromJson(body);
      await _storage.saveUser(user: result.user);
      await _storage.saveTokens(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
      );
      await _storage.saveSessionData({
        'settings': result.session.settings,
      });
      return result;
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  @override
  Future<void> logout() async {
    final refreshToken = await _storage.getRefreshToken();
    try {
      if (refreshToken != null) {
        await _api.post<dynamic>(
          '/auth/logout',
          data: {'refresh_token': refreshToken},
        );
      }
    } on DioException {
      // Ignored: best-effort logout clean up
    } finally {
      await _storage.clear();
    }
  }

  @override
  Future<bool> isAuthenticated() async {
    final token = await _storage.getAccessToken();
    return token != null && token.isNotEmpty;
  }

  @override
  Future<void> registerDeviceToken(String token) async {
    try {
      await _api.post(
        '/device-tokens',
        data: {'token': token, 'platform': _getPlatformName()},
      );
    } on DioException {
      // Ignored: best-effort device token registration
    }
  }
}

String _getPlatformName() {
  if (kIsWeb) return 'web';
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  return 'desktop';
}

/// HTTP repository for the Settings endpoints.
///
/// Each public method is a one-liner that:
///   1. Issues the HTTP call via [ApiClient.dio].
///   2. Translates a [DioException] into the typed [ApiException]
///      hierarchy so the UI can pattern-match on failure modes without
///      knowing about Dio.
///   3. Returns the parsed domain model from [settings_models.dart].
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/settings/data/settings_models.dart';

/// Paths used by the settings repository.
///
/// Centralised so a backend rename only touches one place.
class _SettingsRoutes {
  _SettingsRoutes._();

  static const String settings = '/settings';
  static const String mcpToken = '/auth/mcp-token';
}

abstract class ISettingsRepository {
  Future<UserSettings> getSettings();
  Future<UserSettings> updateSettings({
    String? timezone,
    Map<String, dynamic>? preferences,
  });
  Future<String> generateMcpToken();
}

class SettingsRepository implements ISettingsRepository {
  SettingsRepository({required ApiClient apiClient}) : _api = apiClient;

  final ApiClient _api;

  // ---------------------------------------------------------------------------
  // Settings (timezone, created/updated timestamps)
  // ---------------------------------------------------------------------------

  /// `GET /settings` → the user's [UserSettings].
  @override
  Future<UserSettings> getSettings() async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        _SettingsRoutes.settings,
      );
      final body = response.data;
      if (body == null) {
        throw const ServerException(
          message: 'Resposta vazia do servidor',
          statusCode: 500,
        );
      }
      return UserSettings.fromJson(body);
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  /// `PUT /settings` with optional [timezone] and/or [preferences].
  @override
  Future<UserSettings> updateSettings({
    String? timezone,
    Map<String, dynamic>? preferences,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (timezone != null) data['timezone'] = timezone;
      if (preferences != null) data['preferences'] = preferences;

      final response = await _api.put<Map<String, dynamic>>(
        _SettingsRoutes.settings,
        data: data,
      );
      final body = response.data;
      if (body == null) {
        throw const ServerException(
          message: 'Resposta vazia do servidor',
          statusCode: 500,
        );
      }
      return UserSettings.fromJson(body);
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // MCP token
  // ---------------------------------------------------------------------------

  /// `POST /auth/mcp-token` → a fresh MCP bearer token.
  @override
  Future<String> generateMcpToken() async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        _SettingsRoutes.mcpToken,
      );
      final body = response.data;
      if (body == null) {
        throw const ServerException(
          message: 'Resposta vazia do servidor',
          statusCode: 500,
        );
      }
      return body['mcp_token'] as String;
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }
}

/// Single shared [SettingsRepository] wired to the app-wide
/// [apiClientProvider].
final settingsRepositoryProvider = Provider.autoDispose<ISettingsRepository>((
  ref,
) {
  return SettingsRepository(apiClient: ref.watch(apiClientProvider));
});

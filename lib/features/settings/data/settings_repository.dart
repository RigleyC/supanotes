/// HTTP repository for the Settings/SOUL/Contexts endpoints.
///
/// All three resources share a single repository because they are all
/// thin CRUD surfaces consumed by the same settings UI. Each public
/// method is a one-liner that:
///   1. Issues the HTTP call via [ApiClient.dio].
///   2. Translates a [DioException] into the typed [ApiException]
///      hierarchy so the UI can pattern-match on failure modes without
///      knowing about Dio.
///   3. Returns the parsed domain model from [settings_models.dart].
///
/// The repository is intentionally remote-only: settings, SOUL, and the
/// list of contexts are not part of the offline sync graph (the sync
/// service in `core/sync` pulls contexts for the notes feature, but the
/// settings UI uses fresh reads/writes so the displayed values match
/// the source of truth).
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
  static const String soul = '/soul';
  static const String contexts = '/contexts';

  static String contextById(String id) => '/contexts/$id';
}

abstract class ISettingsRepository {
  Future<UserSettings> getSettings();
  Future<UserSettings> updateSettings(String timezone);
  Future<Soul> getSoul();
  Future<Soul> updateSoul(String personality);
  Future<List<UserContext>> getContexts();
  Future<UserContext> createContext(String name);
  Future<void> deleteContext(String id);
}

class SettingsRepository implements ISettingsRepository {
  SettingsRepository({required ApiClient apiClient}) : _dio = apiClient.dio;

  final Dio _dio;

  // ---------------------------------------------------------------------------
  // Settings (timezone, created/updated timestamps)
  // ---------------------------------------------------------------------------

  /// `GET /settings` → the user's [UserSettings].
  Future<UserSettings> getSettings() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
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

  /// `PUT /settings` with a new IANA [timezone] string.
  Future<UserSettings> updateSettings(String timezone) async {
    try {
      final response = await _dio.put<Map<String, dynamic>>(
        _SettingsRoutes.settings,
        data: {'timezone': timezone},
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
  // SOUL (agent persona prompt)
  // ---------------------------------------------------------------------------

  /// `GET /soul` → the user's [Soul] (persona prompt).
  Future<Soul> getSoul() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _SettingsRoutes.soul,
      );
      final body = response.data;
      if (body == null) {
        throw const ServerException(
          message: 'Resposta vazia do servidor',
          statusCode: 500,
        );
      }
      return Soul.fromJson(body);
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  /// `PUT /soul` with the new [personality] markdown.
  Future<Soul> updateSoul(String personality) async {
    try {
      final response = await _dio.put<Map<String, dynamic>>(
        _SettingsRoutes.soul,
        data: {'personality': personality},
      );
      final body = response.data;
      if (body == null) {
        throw const ServerException(
          message: 'Resposta vazia do servidor',
          statusCode: 500,
        );
      }
      return Soul.fromJson(body);
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // Contexts (user-owned folders)
  // ---------------------------------------------------------------------------

  /// `GET /contexts` → the user's [UserContext] list.
  Future<List<UserContext>> getContexts() async {
    try {
      final response = await _dio.get<List<dynamic>>(
        _SettingsRoutes.contexts,
      );
      final body = response.data ?? const [];
      return body
          .map((raw) => UserContext.fromJson(raw as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  /// `POST /contexts` with a human-readable [name].
  ///
  /// The backend requires both a `name` and a `slug`; we derive the slug
  /// from the name client-side via [slugifyContextName] so the UI only
  /// has to ask the user for one value.
  Future<UserContext> createContext(String name) async {
    final trimmed = name.trim();
    final slug = slugifyContextName(trimmed);
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _SettingsRoutes.contexts,
        data: {'name': trimmed, 'slug': slug},
      );
      final body = response.data;
      if (body == null) {
        throw const ServerException(
          message: 'Resposta vazia do servidor',
          statusCode: 500,
        );
      }
      return UserContext.fromJson(body);
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  /// `DELETE /contexts/:id`.
  Future<void> deleteContext(String id) async {
    try {
      await _dio.delete<dynamic>(_SettingsRoutes.contextById(id));
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }
}

/// Best-effort conversion from a human-readable context name to the
/// `slug` shape the backend validator accepts (lowercase, no spaces,
/// max 50 chars).
///
/// Falls back to `'context'` when the input strips down to the empty
/// string so the POST does not fail validation client-side; the backend
/// is still the source of truth for uniqueness conflicts.
String slugifyContextName(String name) {
  final lowered = name.toLowerCase().trim();
  final replaced = lowered.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  final stripped = replaced.replaceAll(RegExp(r'^-+|-+$'), '');
  if (stripped.isEmpty) return 'context';
  return stripped.length > 50 ? stripped.substring(0, 50) : stripped;
}

/// Single shared [SettingsRepository] wired to the app-wide
/// [apiClientProvider].
final settingsRepositoryProvider = Provider<ISettingsRepository>((ref) {
  return SettingsRepository(apiClient: ref.watch(apiClientProvider));
});

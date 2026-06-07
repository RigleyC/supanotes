/// HTTP repository for the `/routines` endpoints exposed by the
/// backend.
///
/// All methods are thin wrappers around a single Dio call: issue the
/// request, translate the response into a domain model, map any
/// [DioException] into a typed [ApiException] so the UI never sees
/// transport-level types. The repository deliberately knows nothing
/// about Riverpod — it is wired up in [routinesRepositoryProvider].
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/di/providers.dart';

import '../domain/routine_log_model.dart';
import '../domain/routine_model.dart';

abstract class IRoutinesRepository {
  Future<List<RoutineModel>> getRoutines();
  Future<List<RoutineLogModel>> getLogs();
  Future<RoutineModel> updateRoutine(String id, {String? cronExpr, bool? enabled});
  Future<String> testDaily();
  Future<String> testWeekly();
}

class RoutinesRepository implements IRoutinesRepository {
  RoutinesRepository({required ApiClient apiClient}) : _dio = apiClient.dio;

  final Dio _dio;

  /// `GET /routines` → list of configured briefs for the user.
  Future<List<RoutineModel>> getRoutines() async {
    try {
      final response = await _dio.get<dynamic>('/routines');
      final raw = response.data;
      if (raw is! List) {
        return const [];
      }
      return raw
          .whereType<Map<String, dynamic>>()
          .map(RoutineModel.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  /// `GET /routines/logs` → execution history, newest-first ordering
  /// is the backend's responsibility.
  Future<List<RoutineLogModel>> getLogs() async {
    try {
      final response = await _dio.get<dynamic>('/routines/logs');
      final raw = response.data;
      if (raw is! List) {
        return const [];
      }
      return raw
          .whereType<Map<String, dynamic>>()
          .map(RoutineLogModel.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  /// `PATCH /routines/:id` with the given (optional) field changes.
  /// Returns the updated routine as echoed by the backend.
  Future<RoutineModel> updateRoutine(
    String id, {
    String? cronExpr,
    bool? enabled,
  }) async {
    final body = <String, dynamic>{};
    if (cronExpr != null) body['cron_expr'] = cronExpr;
    if (enabled != null) body['enabled'] = enabled;

    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/routines/$id',
        data: body,
      );
      final data = response.data;
      if (data == null) {
        throw const ServerException(
          message: 'Resposta vazia do servidor',
          statusCode: 500,
        );
      }
      return RoutineModel.fromJson(data);
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  /// `POST /routines/daily/test` → dry-run, returns the brief body
  /// the LLM produced for the user's current context.
  Future<String> testDaily() => _testBrief(BriefType.daily);

  /// `POST /routines/weekly/test` → dry-run for the weekly brief.
  Future<String> testWeekly() => _testBrief(BriefType.weekly);

  Future<String> _testBrief(BriefType type) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/routines/${type.testPath}/test',
      );
      final data = response.data;
      if (data == null) {
        throw const ServerException(
          message: 'Resposta vazia do servidor',
          statusCode: 500,
        );
      }
      final content = data['content'];
      if (content is! String) {
        throw const ServerException(
          message: 'Resposta sem conteúdo do brief',
          statusCode: 500,
        );
      }
      return content;
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }
}

/// Single shared [RoutinesRepository] wired to the app-wide
/// [apiClientProvider]. Reading this provider is the entry point used
/// by every routines widget.
final routinesRepositoryProvider = Provider<IRoutinesRepository>((ref) {
  return RoutinesRepository(apiClient: ref.watch(apiClientProvider));
});

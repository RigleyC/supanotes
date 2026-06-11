library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/di/providers.dart';

import '../domain/memory_model.dart';

abstract class IMemoriesRepository {
  Future<List<MemoryModel>> getMemories();
  Future<MemoryModel> createMemory({required String content, String? contextSlug});
  Future<MemoryModel> updateMemory(String id, {required String content});
  Future<void> deleteMemory(String id);
}

class MemoriesRepository implements IMemoriesRepository {
  MemoriesRepository({required ApiClient apiClient}) : _api = apiClient;

  final ApiClient _api;

  @override
  Future<List<MemoryModel>> getMemories() async {
    try {
      final response = await _api.get<dynamic>('/memories');
      final raw = response.data;
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(MemoryModel.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  @override
  Future<MemoryModel> createMemory({
    required String content,
    String? contextSlug,
  }) async {
    try {
      final body = <String, dynamic>{'content': content};
      if (contextSlug != null) body['context_slug'] = contextSlug;
      final response = await _api.post<Map<String, dynamic>>(
        '/memories',
        data: body,
      );
      final data = response.data;
      if (data == null) {
        throw const ServerException(
          message: 'Resposta vazia do servidor',
          statusCode: 500,
        );
      }
      return MemoryModel.fromJson(data);
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  @override
  Future<MemoryModel> updateMemory(String id, {required String content}) async {
    try {
      final response = await _api.put<Map<String, dynamic>>(
        '/memories/$id',
        data: <String, dynamic>{'content': content},
      );
      final data = response.data;
      if (data == null) {
        throw const ServerException(
          message: 'Resposta vazia do servidor',
          statusCode: 500,
        );
      }
      return MemoryModel.fromJson(data);
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  @override
  Future<void> deleteMemory(String id) async {
    try {
      await _api.delete<dynamic>('/memories/$id');
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }
}

final memoriesRepositoryProvider = Provider<IMemoriesRepository>((ref) {
  return MemoriesRepository(apiClient: ref.watch(apiClientProvider));
});

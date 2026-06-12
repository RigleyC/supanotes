library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/search/domain/search_result_model.dart';

abstract class ISearchRepository {
  static const int defaultLimit = 10;

  Future<List<SearchResultModel>> search({
    required String query,
    int limit = defaultLimit,
  });
}

class SearchRepository implements ISearchRepository {
  SearchRepository({required ApiClient apiClient}) : _api = apiClient;

  final ApiClient _api;
  static const int defaultLimit = 10;

  @override
  Future<List<SearchResultModel>> search({
    required String query,
    int limit = defaultLimit,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    try {
      final response = await _api.post<List<dynamic>>(
        '/search',
        data: {
          'query': trimmed,
          'limit': limit,
        },
      );
      final body = response.data ?? const [];
      return body
          .whereType<Map<String, dynamic>>()
          .map(SearchResultModel.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }
}

final searchRepositoryProvider = Provider.autoDispose<ISearchRepository>((ref) {
  return SearchRepository(apiClient: ref.watch(apiClientProvider));
});

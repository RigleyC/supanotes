/// HTTP repository for the `/api/v1/search` endpoint.
///
/// This is the only place in the app that calls the backend search
/// service. It owns the JSON shape (no `mode` field on the wire — the
/// repository injects it from the request), wraps Dio errors in the
/// typed [ApiException] hierarchy, and exposes the result as a list of
/// presentation-friendly [SearchResultModel]s.
///
/// The repository is **online-only**: there is no local search index.
/// If the device is offline the call will surface a
/// [NetworkException], which the screen turns into an empty error
/// state. There is no retry / caching layer here on purpose — search
/// results are stateless and cheap to re-issue.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/search/domain/search_result_model.dart';

abstract class ISearchRepository {
  static const int defaultLimit = 10;

  Future<List<SearchResultModel>> search({required String query, SearchMode mode = SearchMode.hybrid, int limit = defaultLimit});
}

class SearchRepository implements ISearchRepository {
  SearchRepository({required ApiClient apiClient}) : _api = apiClient;

  final ApiClient _api;

  /// Default `limit` the backend falls back to when the request omits
  /// (or sends a non-positive) value. Kept in sync with
  /// `backend/internal/search/handler.go` so behaviour is the same
  /// whether the field is on the wire or not.
  static const int defaultLimit = 10;

  /// `POST /search` → returns at most [limit] hits for [query] using
  /// the requested [mode].
  ///
  /// An empty or whitespace-only [query] short-circuits to an empty
  /// list without touching the network — the screen uses this to keep
  /// the input live without spamming the backend.
  @override
  Future<List<SearchResultModel>> search({
    required String query,
    SearchMode mode = SearchMode.hybrid,
    int limit = defaultLimit,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    try {
      final response = await _api.post<List<dynamic>>(
        '/search',
        data: {
          'query': trimmed,
          'mode': mode.wireValue,
          'limit': limit,
        },
      );
      final body = response.data ?? const [];
      return body
          .whereType<Map<String, dynamic>>()
          .map((json) => SearchResultModel.fromJson(json, mode: mode))
          .toList(growable: false);
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }
}

/// Single shared [SearchRepository] wired to the app-wide
/// [apiClientProvider].
final searchRepositoryProvider = Provider.autoDispose<ISearchRepository>((ref) {
  return SearchRepository(apiClient: ref.watch(apiClientProvider));
});

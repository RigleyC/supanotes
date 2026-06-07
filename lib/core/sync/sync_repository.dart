/// Thin HTTP layer for the sync push/pull endpoints.
///
/// Owns no state — every call goes straight to [ApiClient] which handles
/// auth headers, base URL and timeout. The repository exists so
/// [SyncService] can be tested with a fake [ApiClient] instead of mocking
/// Dio directly.
library;

import 'package:supanotes/core/api/api_client.dart';

class SyncRepository {
  final ApiClient _api;

  SyncRepository({required ApiClient apiClient}) : _api = apiClient;

  /// Sends a batch of dirty local rows to the backend.
  Future<void> push(Map<String, dynamic> payload) async {
    await _api.post('/sync/push', data: payload);
  }

  /// Fetches remote changes since [lastSyncedAt].
  ///
  /// Returns the raw JSON map — the caller ([SyncMapper]) is responsible
  /// for converting it into typed data objects.
  Future<Map<String, dynamic>> pull({
    required String lastSyncedAt,
    int limit = 500,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/sync/pull',
      data: {'last_synced_at': lastSyncedAt, 'limit': limit},
    );
    return response.data ?? const <String, dynamic>{};
  }
}

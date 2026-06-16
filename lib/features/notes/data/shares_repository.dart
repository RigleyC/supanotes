import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/api/api_exceptions.dart';
import '../../../../core/di/providers.dart';

final sharesRepositoryProvider = Provider.autoDispose<SharesRepository>(
  (ref) => SharesRepository(ref.watch(apiClientProvider)),
);

/// Repository for managing note shares on the backend.
///
/// Keeps the HTTP client details out of the presentation layer and maps
/// transport errors to typed [ApiException]s.
class SharesRepository {
  SharesRepository(this._api);

  final ApiClient _api;

  Future<void> shareNote({
    required String noteId,
    required String email,
    required String permission,
  }) async {
    try {
      await _api.post('/notes/$noteId/shares', data: {
        'email': email,
        'permission': permission,
      });
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }
}

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/notes/sharing/model/share_model.dart';
import 'package:supanotes/features/notes/sharing/model/share_permission.dart';

final Provider<SharesRepository> sharesRepositoryProvider = Provider.autoDispose<SharesRepository>(
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
    required SharePermission permission,
  }) async {
    try {
      await _api.post<dynamic>(
        '/notes/$noteId/shares',
        data: {'email': email, 'permission': permission.toJson()},
      );
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  Future<List<ShareModel>> listShares({required String noteId}) async {
    try {
      final response = await _api.get<dynamic>('/notes/$noteId/shares');
      final data = response.data as List;
      return data
          .map((j) => ShareModel.fromJson(j as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  Future<void> deleteShare({
    required String noteId,
    required String userId,
  }) async {
    try {
      await _api.delete<dynamic>('/notes/$noteId/shares/$userId');
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }
}

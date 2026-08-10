import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/notes/sharing/model/share_link_model.dart';

final shareLinkRepositoryProvider = Provider.autoDispose<ShareLinkRepository>(
  (ref) => ShareLinkRepository(ref.watch(apiClientProvider)),
);

class ShareLinkRepository {
  ShareLinkRepository(this._api);

  final ApiClient _api;

  Future<ShareLinkModel> status(String noteId) async {
    try {
      final response = await _api.get('/notes/$noteId/share-link');
      return ShareLinkModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (error) {
      throw fromDioError(error);
    }
  }

  Future<ShareLinkModel> activate(String noteId, {bool replace = false}) async {
    try {
      final response = await _api.post(
        '/notes/$noteId/share-link',
        data: {'replace': replace},
      );
      return ShareLinkModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (error) {
      throw fromDioError(error);
    }
  }

  Future<void> disable(String noteId) async {
    try {
      await _api.delete('/notes/$noteId/share-link');
    } on DioException catch (error) {
      throw fromDioError(error);
    }
  }
}

final shareLinkStatusProvider = FutureProvider.autoDispose
    .family<ShareLinkModel, String>((ref, noteId) {
      return ref.watch(shareLinkRepositoryProvider).status(noteId);
    });

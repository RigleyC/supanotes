import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/notes/sharing/model/share_link_model.dart';

final shareLinkRepositoryProvider = Provider.autoDispose<IShareLinkRepository>(
  (ref) => ShareLinkRepository(ref.watch(apiClientProvider)),
);

abstract interface class IShareLinkRepository {
  Future<ShareLinkModel> status(String noteId);

  Future<ShareLinkModel> activate(String noteId, {bool replace = false});

  Future<void> disable(String noteId);
}

class ShareLinkRepository implements IShareLinkRepository {
  ShareLinkRepository(this._api);

  final ApiClient _api;

  @override
  Future<ShareLinkModel> status(String noteId) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        '/notes/$noteId/share-link',
      );
      return _parse(response.data);
    } on DioException catch (error) {
      throw fromDioError(error);
    }
  }

  @override
  Future<ShareLinkModel> activate(String noteId, {bool replace = false}) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        '/notes/$noteId/share-link',
        data: {'replace': replace},
      );
      return _parse(response.data);
    } on DioException catch (error) {
      throw fromDioError(error);
    }
  }

  @override
  Future<void> disable(String noteId) async {
    try {
      await _api.delete('/notes/$noteId/share-link');
    } on DioException catch (error) {
      throw fromDioError(error);
    }
  }

  ShareLinkModel _parse(Map<String, dynamic>? body) {
    if (body == null) {
      throw const ServerException(
        message: 'Resposta vazia do servidor',
        statusCode: 500,
      );
    }
    try {
      return ShareLinkModel.fromJson(body);
    } on FormatException catch (error) {
      throw ServerException(message: error.message, statusCode: 500);
    }
  }
}

final shareLinkStatusProvider = FutureProvider.autoDispose
    .family<ShareLinkModel, String>((ref, noteId) {
      return ref.watch(shareLinkRepositoryProvider).status(noteId);
    });

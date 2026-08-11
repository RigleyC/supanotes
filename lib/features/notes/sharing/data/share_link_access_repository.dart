import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/notes/sharing/application/share_link_access_resolver.dart';
import 'package:supanotes/features/notes/catalog/model/remote_note_metadata.dart';

final shareLinkAccessRepositoryProvider =
    Provider.autoDispose<ShareLinkAccessRepository>(
      (ref) => ShareLinkAccessRepository(ref.watch(apiClientProvider)),
    );

class ShareLinkAccessRepository implements ShareLinkAccessGateway {
  ShareLinkAccessRepository(this._api);

  final ApiClient _api;

  @override
  Future<ShareLinkTarget> validateToken(String token) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        '/s/${Uri.encodeComponent(token)}/access',
      );
      final data = response.data;
      if (data == null) {
        throw const FormatException('Empty share link response');
      }
      return ShareLinkTarget.fromJson(data);
    } on DioException catch (error) {
      throw fromDioError(error);
    }
  }

  @override
  Future<RemoteNoteMetadata?> metadataFor(String noteId) async {
    try {
      final response = await _api.get<Map<String, dynamic>>('/notes/$noteId');
      final data = response.data;
      if (data == null) {
        throw const FormatException('Empty note response');
      }
      return RemoteNoteMetadata.fromJson(Map<String, dynamic>.from(data));
    } on NotFoundException catch (_) {
      return null;
    } on UnauthorizedException catch (_) {
      return null;
    } on DioException catch (error) {
      throw fromDioError(error);
    }
  }
}

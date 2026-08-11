import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/constants/api_constants.dart';
import 'package:supanotes/features/notes/attachments/domain/attachment_delivery.dart';

/// Resolves attachments through the authenticated attachment endpoint.
///
/// Normal editor access must not depend on a revocable public share token.
final class AuthenticatedAttachmentDelivery implements AttachmentDelivery {
  AuthenticatedAttachmentDelivery(
    this._api, {
    this.preference = AttachmentDeliveryPreference.externalFirst,
  });

  final ApiClient _api;

  @override
  final AttachmentDeliveryPreference preference;

  @override
  Uri urlFor(String attachmentId) {
    final base = Uri.parse(ApiConstants.baseUrl);
    return base.replace(
      path:
          '${base.path}/attachments/${Uri.encodeComponent(attachmentId)}/content',
      query: null,
      fragment: null,
    );
  }

  @override
  Future<void> open(String attachmentId, Uri uri, {String? fileName}) async {
    final response = await _api.get<List<int>>(
      '/attachments/${Uri.encodeComponent(attachmentId)}/content',
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = response.data;
    if (bytes == null) throw StateError('Attachment response has no content');
    final directory = await getTemporaryDirectory();
    final safeName = (fileName ?? 'attachment').replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
    final file = File('${directory.path}/supanotes-$attachmentId-$safeName');
    await file.writeAsBytes(bytes, flush: true);
    if (!await launchUrl(Uri.file(file.path))) {
      throw StateError('Could not open downloaded attachment');
    }
  }
}

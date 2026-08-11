import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:supanotes/core/api/api_client.dart';
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
  @override
  Future<void> open(AttachmentReference attachment) async {
    final response = await _api.get<List<int>>(
      '/attachments/${Uri.encodeComponent(attachment.id)}/content',
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = response.data;
    if (bytes == null) throw StateError('Attachment response has no content');
    final directory = await getTemporaryDirectory();
    final safeName = attachment.fileName.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
    final file = File('${directory.path}/supanotes-${attachment.id}-$safeName');
    await file.writeAsBytes(bytes, flush: true);
    if (!await launchUrl(Uri.file(file.path))) {
      throw StateError('Could not open downloaded attachment ${attachment.id}');
    }
  }
}

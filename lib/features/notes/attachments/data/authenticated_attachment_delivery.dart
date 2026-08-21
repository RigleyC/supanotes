import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/features/notes/attachments/domain/attachment_delivery.dart';
import 'package:url_launcher/url_launcher.dart';

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
  Future<void> open(AttachmentReference attachment) async {
    final response = await _api.get<ResponseBody>(
      '/attachments/${Uri.encodeComponent(attachment.id)}/content',
      options: Options(responseType: ResponseType.stream),
    );
    final body = response.data;
    if (body == null) throw StateError('Attachment response has no content');
    final directory = await getTemporaryDirectory();
    final safeName = attachment.fileName.replaceAll(
      RegExp('[^A-Za-z0-9._-]'),
      '_',
    );
    final file = File('${directory.path}/supanotes-${attachment.id}-$safeName');
    IOSink? sink;
    try {
      sink = file.openWrite();
      await for (final chunk in body.stream) {
        sink.add(chunk);
      }
      await sink.close();
      sink = null;
    } catch (_) {
      await sink?.close();
      try {
        await file.delete();
      } catch (_) {
        // The partial file is best-effort cleanup after a failed download.
      }
      rethrow;
    }
    if (!await launchUrl(Uri.file(file.path))) {
      throw StateError('Could not open downloaded attachment ${attachment.id}');
    }
  }
}

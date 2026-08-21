import 'package:supanotes/core/constants/api_constants.dart';
import 'package:supanotes/features/notes/attachments/domain/attachment_delivery.dart';
import 'package:url_launcher/url_launcher.dart';

/// Builds the browser-deliverable attachment URL for a public share token.
///
/// URL construction belongs to the data boundary. Presentation components
/// only receive the resolved URI and never need to know that the API client
/// base path contains `/api/v1`.
Uri shareLinkAttachmentUrl(String token, String attachmentId) {
  final base = ApiConstants.publicBaseUri;
  final rootPath = base.path;
  return base.replace(
    path:
        '${rootPath.isEmpty ? '' : rootPath}/s/${Uri.encodeComponent(token)}/attachments/${Uri.encodeComponent(attachmentId)}',
  );
}

final class ShareLinkAttachmentDelivery implements AttachmentDelivery {
  const ShareLinkAttachmentDelivery(
    this.token, {
    this.preference = AttachmentDeliveryPreference.externalFirst,
  });

  final String token;

  @override
  final AttachmentDeliveryPreference preference;

  @override
  Future<void> open(AttachmentReference attachment) =>
      launchUrl(shareLinkAttachmentUrl(token, attachment.id)).then((opened) {
        if (!opened) {
          throw StateError('Could not open shared attachment');
        }
      });
}

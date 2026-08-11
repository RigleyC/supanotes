import 'package:supanotes/core/constants/api_constants.dart';
import 'package:supanotes/features/notes/attachments/domain/attachment_delivery.dart';

/// Builds the browser-deliverable attachment URL for a public share token.
///
/// URL construction belongs to the data boundary. Presentation components
/// only receive the resolved URI and never need to know that the API client
/// base path contains `/api/v1`.
Uri shareLinkAttachmentUrl(String token, String attachmentId) {
  final base = Uri.parse(ApiConstants.baseUrl);
  const apiPath = '/api/v1';
  final rootPath = base.path.endsWith(apiPath)
      ? base.path.substring(0, base.path.length - apiPath.length)
      : base.path;
  return base.replace(
    path:
        '${rootPath.isEmpty ? '' : rootPath}/s/${Uri.encodeComponent(token)}/attachments/${Uri.encodeComponent(attachmentId)}',
    query: null,
    fragment: null,
  );
}

final class ShareLinkAttachmentDelivery implements AttachmentDelivery {
  const ShareLinkAttachmentDelivery(this.token);

  final String token;

  @override
  Uri urlFor(String attachmentId) =>
      shareLinkAttachmentUrl(token, attachmentId);
}

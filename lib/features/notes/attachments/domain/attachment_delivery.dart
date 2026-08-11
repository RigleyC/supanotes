/// Resolves a download URL for an attachment that is not present locally.
///
/// The editor only depends on this delivery contract. Public share links and
/// authenticated attachment endpoints provide their own implementations at
/// the composition boundary.
abstract interface class AttachmentDelivery {
  Uri? urlFor(String attachmentId);
}

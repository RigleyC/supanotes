enum AttachmentDeliveryPreference { localFirst, externalFirst }

final class AttachmentReference {
  const AttachmentReference({required this.id, required this.fileName});

  final String id;
  final String fileName;

  @override
  bool operator ==(Object other) =>
      other is AttachmentReference &&
      other.id == id &&
      other.fileName == fileName;

  @override
  int get hashCode => Object.hash(id, fileName);
}

/// Resolves a download URL for an attachment that is not present locally.
///
/// The editor only depends on this delivery contract. Public share links and
/// authenticated attachment endpoints provide their own implementations at
/// the composition boundary.
abstract interface class AttachmentDelivery {
  AttachmentDeliveryPreference get preference;
  Future<void> open(AttachmentReference attachment);
}

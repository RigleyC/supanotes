final class PendingShare {
  const PendingShare({
    required this.shareId,
    required this.text,
    this.noteId,
    this.ownerUserId,
  });

  factory PendingShare.fromMap(Map<String, dynamic> map) {
    return PendingShare(
      shareId: map['shareId'] as String? ?? '',
      text: map['text'] as String? ?? '',
      noteId: (map['noteId'] as String?)?.trim().isEmpty ?? true
          ? null
          : map['noteId'] as String?,
      ownerUserId: (map['ownerUserId'] as String?)?.trim().isEmpty ?? true
          ? null
          : map['ownerUserId'] as String?,
    );
  }

  final String shareId;
  final String text;
  final String? noteId;
  final String? ownerUserId;

  bool isValidForUser(String currentUserId) {
    if (ownerUserId == null || ownerUserId!.isEmpty) {
      return true;
    }
    return ownerUserId == currentUserId;
  }
}

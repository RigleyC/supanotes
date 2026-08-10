import 'package:supanotes/features/auth/domain/user.dart';

enum ShareLinkAccessMode { editor, viewer, guest }

class ShareLinkTarget {
  const ShareLinkTarget({required this.noteId});

  final String noteId;

  factory ShareLinkTarget.fromJson(Map<String, dynamic> json) {
    final noteId = json['note_id'];
    if (noteId is! String || noteId.isEmpty) {
      throw const FormatException('Share link response has no note id');
    }
    return ShareLinkTarget(noteId: noteId);
  }
}

class ShareLinkAccessDecision {
  const ShareLinkAccessDecision({required this.noteId, required this.mode});

  final String noteId;
  final ShareLinkAccessMode mode;

  bool get canEdit => mode == ShareLinkAccessMode.editor;
}

abstract interface class ShareLinkAccessGateway {
  Future<ShareLinkTarget> validateToken(String token);

  /// Returns `owner`, `edit`, `view`, or null when the session has no direct
  /// access. A missing direct share does not block the public link.
  Future<String?> permissionFor(String noteId);
}

class ShareLinkAccessResolver {
  ShareLinkAccessResolver(this.gateway);

  final ShareLinkAccessGateway gateway;

  Future<ShareLinkAccessDecision> resolve(String token, {User? user}) async {
    final target = await gateway.validateToken(token);
    if (user == null) {
      return ShareLinkAccessDecision(
        noteId: target.noteId,
        mode: ShareLinkAccessMode.guest,
      );
    }

    final permission = await gateway.permissionFor(target.noteId);
    final mode = switch (permission) {
      'owner' || 'edit' => ShareLinkAccessMode.editor,
      'view' => ShareLinkAccessMode.viewer,
      _ => ShareLinkAccessMode.guest,
    };
    return ShareLinkAccessDecision(noteId: target.noteId, mode: mode);
  }
}

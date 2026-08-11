import 'package:supanotes/features/auth/domain/user.dart';
import 'package:supanotes/features/notes/catalog/model/remote_note_metadata.dart';

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
  const ShareLinkAccessDecision({
    required this.noteId,
    required this.mode,
    this.metadata,
  });

  final String noteId;
  final ShareLinkAccessMode mode;
  final RemoteNoteMetadata? metadata;

  bool get canEdit => mode == ShareLinkAccessMode.editor;
}

abstract interface class ShareLinkAccessGateway {
  Future<ShareLinkTarget> validateToken(String token);

  /// Returns authenticated metadata, or null when the session has no direct
  /// access. A missing direct share does not block the public link.
  Future<RemoteNoteMetadata?> metadataFor(String noteId);
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

    final metadata = await gateway.metadataFor(target.noteId);
    final permission = metadata == null ? null : metadata.permission ?? 'owner';
    final mode = switch (permission) {
      'owner' || 'edit' => ShareLinkAccessMode.editor,
      'view' => ShareLinkAccessMode.viewer,
      _ => ShareLinkAccessMode.guest,
    };
    return ShareLinkAccessDecision(
      noteId: target.noteId,
      mode: mode,
      metadata: metadata,
    );
  }
}

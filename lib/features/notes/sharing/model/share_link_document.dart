import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';

/// Public share response envelope.
///
/// The note snapshot itself belongs to the editor/document layer. Keeping the
/// envelope this small prevents the sharing feature from maintaining a second
/// block registry or Super Editor decoder.
final class ShareLinkDocument {
  const ShareLinkDocument({required this.title, required this.snapshot});

  factory ShareLinkDocument.fromJson(Map<String, dynamic> json) {
    final rawTitle = json['title'];
    if (rawTitle is! String || rawTitle.trim().isEmpty) {
      throw const FormatException('Share link response has no title');
    }
    final rawDocument = json['document'];
    if (rawDocument is! Map) {
      throw const FormatException('Share link response has no document');
    }
    return ShareLinkDocument(
      title: rawTitle,
      snapshot: NoteDocumentSnapshot.fromJson(
        Map<String, dynamic>.from(rawDocument),
      ),
    );
  }

  final String title;
  final NoteDocumentSnapshot snapshot;
}

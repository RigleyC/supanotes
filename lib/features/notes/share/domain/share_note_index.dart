import 'dart:convert';

import 'package:supanotes/features/notes/catalog/model/note_model.dart';

final class ShareNoteIndexEntry {
  const ShareNoteIndexEntry({
    required this.noteId,
    required this.title,
    required this.preview,
    required this.updatedAt,
    required this.canEdit,
  });

  final String noteId;
  final String title;
  final String preview;
  final DateTime updatedAt;
  final bool canEdit;

  Map<String, dynamic> toJson() => {
    'noteId': noteId,
    'title': title,
    'preview': preview,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'canEdit': canEdit,
  };
}

final class ShareNoteIndex {
  const ShareNoteIndex({required this.ownerUserId, required this.notes});

  factory ShareNoteIndex.fromNotes(
    String ownerUserId,
    Iterable<NoteModel> notes,
  ) {
    final entries =
        notes
            .where((note) => !note.isReadOnly)
            .map(
              (note) => ShareNoteIndexEntry(
                noteId: note.id,
                title: note.title,
                preview: note.excerpt ?? note.content,
                updatedAt: note.updatedAt,
                canEdit: true,
              ),
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return ShareNoteIndex(ownerUserId: ownerUserId, notes: entries);
  }

  final String ownerUserId;
  final List<ShareNoteIndexEntry> notes;

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'ownerUserId': ownerUserId,
    'notes': notes.map((note) => note.toJson()).toList(growable: false),
  };

  String encode() => jsonEncode(toJson());
}

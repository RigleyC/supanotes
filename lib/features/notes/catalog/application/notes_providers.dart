import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/features/notes/catalog/data/notes_repository.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';

final activeNotesProvider = StreamProvider.autoDispose<List<NoteModel>>((ref) {
  return ref.watch(notesRepositoryProvider).watchNotes();
});

final noteProvider = StreamProvider.autoDispose.family<NoteModel?, String>(
  (ref, noteId) => ref.watch(notesRepositoryProvider).watchNoteById(noteId),
);

/// Ids of notes whose full content matches a lower-cased search query.
///
/// Re-evaluated when the catalog changes so results follow edits and syncs.
final noteSearchMatchesProvider = FutureProvider.autoDispose
    .family<Set<String>, String>((
      ref,
      normalizedQuery,
    ) {
      ref.watch(activeNotesProvider);
      return ref.read(notesRepositoryProvider).searchNoteIds(normalizedQuery);
    });

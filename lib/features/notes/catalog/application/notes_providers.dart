import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/features/notes/catalog/data/notes_repository.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';

final activeNotesProvider = StreamProvider.autoDispose<List<NoteModel>>((ref) {
  return ref.watch(notesRepositoryProvider).watchNotes();
});

final noteProvider = StreamProvider.autoDispose.family<NoteModel?, String>(
  (ref, noteId) => ref.watch(notesRepositoryProvider).watchNoteById(noteId),
);

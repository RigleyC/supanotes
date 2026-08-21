import 'package:riverpod/src/providers/stream_provider.dart';

import 'package:supanotes/features/notes/catalog/data/notes_repository.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';

final StreamProvider<List<NoteModel>> activeNotesProvider = StreamProvider.autoDispose<List<NoteModel>>((ref) {
  return ref.watch(notesRepositoryProvider).watchNotes();
});

final StreamProviderFamily<NoteModel?, String> noteProvider = StreamProvider.autoDispose.family<NoteModel?, String>(
  (ref, noteId) => ref.watch(notesRepositoryProvider).watchNoteById(noteId),
);

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';

final inboxProvider = StreamProvider.autoDispose<NoteModel?>((ref) {
  return ref.watch(notesRepositoryProvider).watchInbox();
});

final activeNotesProvider = StreamProvider.autoDispose<List<NoteModel>>((ref) {
  return ref.watch(notesRepositoryProvider).watchNotes();
});


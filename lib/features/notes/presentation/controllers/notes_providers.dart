import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/domain/note_with_tasks.dart';

final inboxProvider = StreamProvider.autoDispose<NoteModel?>((ref) {
  return ref.watch(notesRepositoryProvider).watchInbox();
});

final activeNotesProvider = StreamProvider.autoDispose<List<NoteModel>>((ref) {
  return ref.watch(notesRepositoryProvider).watchNotes();
});

/// Streams a note together with its tasks in a single reactive emission.
///
/// Delegates to a Drift JOIN query that watches both `notes` and `tasks`
/// tables, so the UI rebuilds whenever *either* changes without manual
/// stream merging.
final noteWithTasksProvider =
    StreamProvider.autoDispose.family<NoteWithTasks, String>((ref, noteId) {
  return ref.watch(notesRepositoryProvider).watchNoteWithTasks(noteId);
});

final noteNodesProvider =
    StreamProvider.autoDispose.family<List<NoteNode>, String>((ref, noteId) {
  return ref.watch(notesRepositoryProvider).watchNodes(noteId);
});

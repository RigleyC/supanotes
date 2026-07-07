import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/domain/note_with_tasks.dart';

final activeNotesProvider = StreamProvider.autoDispose<List<NoteModel>>((ref) {
  return ref.watch(notesRepositoryProvider).watchNotes();
});

/// Streams a note together with its tasks in a single reactive emission.
///
/// Delegates to a Drift JOIN query that watches both `notes` and `tasks`
/// tables, so the UI rebuilds whenever *either* changes without manual
/// stream merging.
final noteWithTasksProvider = StreamProvider.autoDispose
    .family<NoteWithTasks, String>((ref, noteId) {
      return ref.watch(notesRepositoryProvider).watchNoteWithTasks(noteId);
    });

final noteNodesProvider = StreamProvider.autoDispose
    .family<List<NoteNode>, String>((ref, noteId) {
      return ref.watch(notesRepositoryProvider).watchNodes(noteId);
    });

final combinedNoteEditorStateProvider = Provider.autoDispose
    .family<AsyncValue<(List<NoteNode>, NoteWithTasks)>, String>((ref, noteId) {
  final nodes = ref.watch(noteNodesProvider(noteId));
  final noteWithTasks = ref.watch(noteWithTasksProvider(noteId));

  if (nodes.hasError) return AsyncValue.error(nodes.error!, nodes.stackTrace!);
  if (noteWithTasks.hasError) return AsyncValue.error(noteWithTasks.error!, noteWithTasks.stackTrace!);

  if (nodes.isLoading || noteWithTasks.isLoading) {
    return const AsyncValue.loading();
  }

  return AsyncValue.data((nodes.requireValue, noteWithTasks.requireValue));
});

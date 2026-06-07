import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';

class NotesListState {
  final List<NoteModel> notes;
  final NoteModel? inbox;
  final bool favoritesOnly;

  const NotesListState({
    this.notes = const [],
    this.inbox,
    this.favoritesOnly = false,
  });

  NotesListState copyWith({
    List<NoteModel>? notes,
    NoteModel? inbox,
    bool? favoritesOnly,
  }) =>
      NotesListState(
        notes: notes ?? this.notes,
        inbox: inbox ?? this.inbox,
        favoritesOnly: favoritesOnly ?? this.favoritesOnly,
      );
}

final notesListControllerProvider =
    AsyncNotifierProvider<NotesListController, NotesListState>(
  NotesListController.new,
);

class NotesListController extends AsyncNotifier<NotesListState> {
  @override
  Future<NotesListState> build() async {
    final repo = ref.read(notesRepositoryProvider);
    final notes = await repo.watchNotes().first;
    final inbox = await repo.watchInbox().first;
    return NotesListState(notes: notes, inbox: inbox);
  }

  void toggleFavoritesOnly() {
    // Will be implemented when notes_list_screen is refactored
  }

  Future<void> toggleFavorite(String noteId) async {
    await ref.read(notesRepositoryProvider).toggleFavorite(noteId);
  }

  Future<void> deleteNote(String noteId) async {
    await ref.read(notesRepositoryProvider).softDelete(noteId);
    final notes = state.value!.notes.where((n) => n.id != noteId).toList();
    state = AsyncValue.data(state.value!.copyWith(notes: notes));
  }

  Future<void> createNote() async {
    final repo = ref.read(notesRepositoryProvider);
    await repo.createNote();
    final notes = await repo.watchNotes().first;
    state = AsyncValue.data(state.value!.copyWith(notes: notes));
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';

class NoteEditorState {
  final NoteModel? note;
  final bool isSaving;
  final DateTime? lastSavedAt;

  const NoteEditorState({
    this.note,
    this.isSaving = false,
    this.lastSavedAt,
  });

  NoteEditorState copyWith({
    NoteModel? note,
    bool? isSaving,
    DateTime? lastSavedAt,
  }) =>
      NoteEditorState(
        note: note ?? this.note,
        isSaving: isSaving ?? this.isSaving,
        lastSavedAt: lastSavedAt ?? this.lastSavedAt,
      );
}

final noteEditorControllerProvider =
    AsyncNotifierProvider<NoteEditorController, NoteEditorState>(
  NoteEditorController.new,
);

class NoteEditorController extends AsyncNotifier<NoteEditorState> {
  @override
  Future<NoteEditorState> build() async {
    return const NoteEditorState();
  }

  Future<void> loadNote(String noteId) async {
    final repo = ref.read(notesRepositoryProvider);
    final notes = await repo.watchNotes().first;
    final note = notes.where((n) => n.id == noteId).firstOrNull;
    state = AsyncValue.data(state.value!.copyWith(note: note));
  }

  Future<void> saveTitle(String title) async {
    final current = state.value!;
    final note = current.note;
    if (note == null) return;
    state = AsyncValue.data(current.copyWith(isSaving: true));
    await ref.read(notesRepositoryProvider).updateNote(note.id, title: title);
    state = AsyncValue.data(
      current.copyWith(
        isSaving: false,
        note: note,
        lastSavedAt: DateTime.now(),
      ),
    );
  }

  Future<void> saveContent(String content) async {
    final current = state.value!;
    final note = current.note;
    if (note == null) return;
    state = AsyncValue.data(current.copyWith(isSaving: true));
    await ref.read(notesRepositoryProvider).updateNote(note.id, content: content);
    state = AsyncValue.data(
      current.copyWith(
        isSaving: false,
        note: note,
        lastSavedAt: DateTime.now(),
      ),
    );
  }

  Future<void> toggleFavorite() async {
    final current = state.value!;
    final note = current.note;
    if (note == null) return;
    await ref.read(notesRepositoryProvider).toggleFavorite(note.id);
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';

final inboxProvider = StreamProvider<NoteModel?>((ref) {
  return ref.watch(notesRepositoryProvider).watchInbox();
});

final activeNotesProvider = StreamProvider<List<NoteModel>>((ref) {
  return ref.watch(notesRepositoryProvider).watchNotes();
});

final favoritesFilterProvider =
    NotifierProvider.autoDispose<FavoritesFilterNotifier, bool>(
  FavoritesFilterNotifier.new,
);

class FavoritesFilterNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

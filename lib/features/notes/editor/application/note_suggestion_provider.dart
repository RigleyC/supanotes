import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/notes/catalog/application/notes_providers.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';

/// Notes that can be linked from the editor `@` suggestion row.
final noteSuggestionsProvider = Provider.family
    .autoDispose<
      AsyncValue<List<NoteModel>>,
      ({String query, String currentNoteId})
    >(
      (ref, params) {
        return ref.watch(activeNotesProvider).whenData((notes) {
          final lowercaseQuery = params.query.toLowerCase();
          return notes
              .where(
                (n) =>
                    n.id != params.currentNoteId &&
                    n.title.toLowerCase().contains(lowercaseQuery),
              )
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        });
      },
    );

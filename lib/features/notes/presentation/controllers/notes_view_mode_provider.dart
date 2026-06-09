import 'package:flutter_riverpod/flutter_riverpod.dart';

enum NotesViewMode { list, grid }

class NotesViewModeNotifier extends Notifier<NotesViewMode> {
  @override
  NotesViewMode build() => NotesViewMode.grid;

  void toggle() {
    state = state == NotesViewMode.grid
        ? NotesViewMode.list
        : NotesViewMode.grid;
  }
}

final notesViewModeProvider =
    NotifierProvider.autoDispose<NotesViewModeNotifier, NotesViewMode>(
  NotesViewModeNotifier.new,
);

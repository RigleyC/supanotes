class NoteSessionActivityTracker {
  final Set<String> _activeNoteIds = <String>{};

  bool isActive(String noteId) => _activeNoteIds.contains(noteId);

  int get activeCount => _activeNoteIds.length;

  Set<String> get activeNoteIds => Set.unmodifiable(_activeNoteIds);

  void markActive(String noteId) {
    _activeNoteIds.add(noteId);
  }

  void markInactive(String noteId) {
    _activeNoteIds.remove(noteId);
  }
}

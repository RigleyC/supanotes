class NoteSessionActivityTracker {
  final Set<String> _activeNoteIds = <String>{};

  bool isActive(String noteId) => _activeNoteIds.contains(noteId);

  void markActive(String noteId) {
    _activeNoteIds.add(noteId);
  }

  void markInactive(String noteId) {
    _activeNoteIds.remove(noteId);
  }
}

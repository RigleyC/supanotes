class NoteSessionActivityTracker {
  final Map<String, Set<String>> _activeSessionKeysByNote = {};

  bool isActive(String noteId) =>
      _activeSessionKeysByNote[noteId]?.isNotEmpty ?? false;

  int get activeCount => _activeSessionKeysByNote.length;

  Set<String> get activeNoteIds =>
      Set.unmodifiable(_activeSessionKeysByNote.keys.toSet());

  void markActive(String noteId, {String? sessionKey}) {
    final keys = _activeSessionKeysByNote.putIfAbsent(noteId, () => {});
    keys.add(sessionKey ?? noteId);
  }

  void markInactive(String noteId, {String? sessionKey}) {
    final keys = _activeSessionKeysByNote[noteId];
    if (keys == null) return;
    keys.remove(sessionKey ?? noteId);
    if (keys.isEmpty) _activeSessionKeysByNote.remove(noteId);
  }
}

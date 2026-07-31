/// Transient options used when opening the note editor.
///
/// These options are navigation state, not note data. They are intentionally
/// passed as route extras so they do not become part of a shareable note URL.
class NoteEditorOpenOptions {
  const NoteEditorOpenOptions({this.requestInitialFocus = false});

  const NoteEditorOpenOptions.newNote() : requestInitialFocus = true;

  final bool requestInitialFocus;
}

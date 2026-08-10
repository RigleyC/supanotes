/// Transient options used when opening the note editor.
///
/// These options are navigation state, not note data. They are intentionally
/// passed as route extras so they do not become part of a shareable note URL.
enum NoteEditorAccessMode { readOnly, editable }

class NoteEditorOpenOptions {
  const NoteEditorOpenOptions({
    this.requestInitialFocus = false,
    this.accessMode,
    this.shareLinkToken,
  });

  const NoteEditorOpenOptions.newNote()
    : requestInitialFocus = true,
      accessMode = NoteEditorAccessMode.editable,
      shareLinkToken = null;

  final bool requestInitialFocus;

  /// Optional access decision supplied by a share-link handoff.
  ///
  /// `null` keeps the permission stored in the local note catalog. A value
  /// from the authenticated share-link resolver is authoritative for this
  /// navigation and also allows a note to open before catalog hydration.
  final NoteEditorAccessMode? accessMode;

  final String? shareLinkToken;
}

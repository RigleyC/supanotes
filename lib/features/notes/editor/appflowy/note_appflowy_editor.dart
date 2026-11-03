import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:supanotes/features/notes/attachments/domain/attachment_delivery.dart';
import 'package:supanotes/features/notes/editor/appflowy/blocks/note_task_block.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_format_commands.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_style.dart';

bool _configured = false;

/// Adapts AppFlowy's global defaults to the SupaNotes document model.
void configureNoteAppFlowy() {
  if (_configured) return;
  _configured = true;
  // Only list items and tasks carry an indent in a synced note.
  indentableBlockTypes.remove(ParagraphBlockKeys.type);
}

// Shortcuts that would create content a synced note cannot store: inline
// code, highlight colors, tables and AppFlowy's own block menu.
// Dividers and indentation are replaced by note-aware versions: a divider
// gets a random illustration, and Tab / Shift+Tab never reorder blocks.
final _replacedCharacterShortcuts = <CharacterShortcutEvent>{
  formatBackquoteToCode,
  slashCommand,
  convertMinusesToDivider,
  convertStarsToDivider,
  convertUnderscoreToDivider,
};
final _replacedCommandShortcuts = <CommandShortcutEvent>{
  toggleCodeCommand,
  toggleHighlightCommand,
  indentCommand,
  outdentCommand,
  ...tableCommands,
};

/// Keyboard and markdown shortcuts available in a note.
final noteCharacterShortcuts = [
  noteDividerShortcut,
  for (final event in standardCharacterShortcutEvents)
    if (!_replacedCharacterShortcuts.contains(event)) event,
];

/// Command shortcuts (undo, formatting, navigation) available in a note.
final noteCommandShortcuts = [
  CommandShortcutEvent(
    key: 'indent note blocks',
    getDescription: () => 'Aumentar recuo',
    command: 'tab',
    handler: (editorState) {
      unawaited(editorState.indentNoteBlocks());
      return KeyEventResult.handled;
    },
  ),
  CommandShortcutEvent(
    key: 'outdent note blocks',
    getDescription: () => 'Diminuir recuo',
    command: 'shift+tab',
    handler: (editorState) {
      unawaited(editorState.outdentNoteBlocks());
      return KeyEventResult.handled;
    },
  ),
  for (final event in standardCommandShortcutEvents)
    if (!_replacedCommandShortcuts.contains(event)) event,
];

/// The note body editor.
class NoteAppFlowyEditor extends StatelessWidget {
  /// Creates the editor for [editorState].
  const NoteAppFlowyEditor({
    required this.editorState,
    super.key,
    this.taskActions = const NoteTaskActions(),
    this.links = const NoteLinkHandler(),
    this.readOnly = false,
    this.hideCompleted = false,
    this.collapseImages = false,
    this.attachmentDelivery,
    this.scrollController,
    this.focusNode,
    this.autoFocus = false,
    this.shrinkWrap = false,
    this.header,
    this.footer,
    this.padding,
  });

  /// The document being edited.
  final EditorState editorState;

  /// What task checkboxes and long presses do.
  final NoteTaskActions taskActions;

  /// What tapping a link does.
  final NoteLinkHandler links;

  /// Shows the note without editing.
  final bool readOnly;

  /// Hides completed tasks.
  final bool hideCompleted;

  /// Shows images as file pills.
  final bool collapseImages;

  /// Where attachments are fetched from (null for local-first).
  final AttachmentDelivery? attachmentDelivery;

  /// Scroll controller; created by the editor when null.
  final EditorScrollController? scrollController;

  /// Keyboard focus of the editor.
  final FocusNode? focusNode;

  /// Places the caret and opens the keyboard on first build.
  final bool autoFocus;

  /// Sizes the editor to its content instead of filling the viewport.
  final bool shrinkWrap;

  /// Shown above the first block (e.g. the title field).
  final Widget? header;

  /// Shown below the last block.
  final Widget? footer;

  /// Space around the document.
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    configureNoteAppFlowy();
    final style = noteEditorStyle(context, links: links);
    return AppFlowyEditor(
      editorState: editorState,
      editable: !readOnly,
      autoFocus: autoFocus,
      focusNode: focusNode,
      shrinkWrap: shrinkWrap,
      editorScrollController: scrollController,
      header: header,
      footer: footer,
      editorStyle: padding == null ? style : style.copyWith(padding: padding),
      characterShortcutEvents: noteCharacterShortcuts,
      commandShortcutEvents: noteCommandShortcuts,
      blockComponentBuilders: noteBlockBuilders(
        context,
        taskActions: taskActions,
        readOnly: readOnly,
        hideCompleted: hideCompleted,
        collapseImages: collapseImages,
        attachmentDelivery: attachmentDelivery,
        allowInternalNoteLinks: links.allowInternalNoteLinks,
      ),
    );
  }
}

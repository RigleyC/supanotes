import 'package:super_editor/super_editor.dart';

import 'markdown_task_shortcut_reaction.dart';

/// Adds the desktop-only Markdown task shortcut to an editor.
class MarkdownTaskShortcutPlugin extends SuperEditorPlugin {
  MarkdownTaskShortcutPlugin()
    : _reaction = const MarkdownTaskShortcutConversionReaction();

  final MarkdownTaskShortcutConversionReaction _reaction;

  @override
  void attach(Editor editor) {
    editor.reactionPipeline.insert(0, _reaction);
  }

  @override
  void detach(Editor editor) {
    editor.reactionPipeline.removeWhere(
      (reaction) => identical(reaction, _reaction),
    );
  }
}

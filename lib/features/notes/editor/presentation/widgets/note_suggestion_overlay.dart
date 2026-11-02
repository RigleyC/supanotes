import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/editor/application/note_suggestion_provider.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_choice_chip.dart';

/// An `@query` being typed right before the caret.
typedef NoteMention = ({Path path, int start, int end, String query});

final _mentionPattern = RegExp(r'@([^\s@]*)$');

/// The `@query` that ends at a collapsed caret, if any.
NoteMention? noteMentionAt(EditorState editorState) {
  final selection = editorState.selection;
  if (selection == null || !selection.isCollapsed) return null;
  final caret = selection.end;
  final delta = editorState.getNodeAtPath(caret.path)?.delta;
  if (delta == null || caret.offset == 0) return null;
  final before = delta.toPlainText().substring(0, caret.offset);
  final match = _mentionPattern.firstMatch(before);
  if (match == null) return null;
  return (
    path: caret.path,
    start: match.start,
    end: caret.offset,
    query: match.group(1)!,
  );
}

/// Replaces [mention] with a link to [note] and puts the caret after it.
Future<void> applyNoteMention(
  EditorState editorState,
  NoteMention mention,
  NoteModel note,
) async {
  final node = editorState.getNodeAtPath(mention.path);
  if (node == null) return;
  final end = mention.start + note.title.length;
  await editorState.apply(
    editorState.transaction
      ..replaceText(
        node,
        mention.start,
        mention.end - mention.start,
        note.title,
        attributes: {AppFlowyRichTextKeys.href: 'note://${note.id}'},
      )
      ..afterSelection = Selection.collapsed(
        Position(path: mention.path, offset: end),
      ),
  );
}

/// The row of notes to link while the user types `@name`.
class NoteSuggestionOverlay extends ConsumerStatefulWidget {
  const NoteSuggestionOverlay({
    required this.editorState,
    required this.currentNoteId,
    super.key,
  });

  final EditorState editorState;
  final String currentNoteId;

  @override
  ConsumerState<NoteSuggestionOverlay> createState() =>
      _NoteSuggestionOverlayState();
}

class _NoteSuggestionOverlayState extends ConsumerState<NoteSuggestionOverlay> {
  NoteMention? _mention;

  @override
  void initState() {
    super.initState();
    widget.editorState.selectionNotifier.addListener(_update);
    _mention = noteMentionAt(widget.editorState);
  }

  @override
  void didUpdateWidget(NoteSuggestionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.editorState != oldWidget.editorState) {
      oldWidget.editorState.selectionNotifier.removeListener(_update);
      widget.editorState.selectionNotifier.addListener(_update);
      _update();
    }
  }

  @override
  void dispose() {
    widget.editorState.selectionNotifier.removeListener(_update);
    super.dispose();
  }

  void _update() {
    final next = noteMentionAt(widget.editorState);
    if (next == _mention) return;
    setState(() => _mention = next);
  }

  @override
  Widget build(BuildContext context) {
    final mention = _mention;
    if (mention == null) return const SizedBox.shrink();

    final suggestions = ref.watch(
      noteSuggestionsProvider((
        query: mention.query,
        currentNoteId: widget.currentNoteId,
      )),
    );
    return suggestions.when(
      data: (notes) {
        if (notes.isEmpty) return const SizedBox.shrink();
        final shown = notes.take(10).toList();
        return SizedBox(
          height: 44,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            itemCount: shown.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: AppChoiceChip(
                label: shown[i].title,
                onTap: () =>
                    applyNoteMention(widget.editorState, mention, shown[i]),
              ),
            ),
          ),
        );
      },
      loading: () => const SizedBox(height: 44),
      error: (_, _) => const SizedBox(
        height: 44,
        child: Center(child: Text('Não foi possível carregar sugestões')),
      ),
    );
  }
}

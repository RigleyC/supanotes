import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/editor/application/note_suggestion_provider.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_suggestion_handler.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_choice_chip.dart';
import 'package:super_editor/super_editor.dart';

class NoteSuggestionOverlay extends ConsumerStatefulWidget {
  const NoteSuggestionOverlay({
    required this.editor,
    required this.composer,
    required this.currentNoteId,
    super.key,
  });
  final Editor editor;
  final DocumentComposer composer;
  final String currentNoteId;

  @override
  ConsumerState<NoteSuggestionOverlay> createState() =>
      _NoteSuggestionOverlayState();
}

class _NoteMatch {
  const _NoteMatch({
    required this.query,
    required this.nodeId,
    required this.tagStart,
    required this.tagEnd,
  });
  final String query;
  final String nodeId;
  final int tagStart;
  final int tagEnd;
}

class _NoteSuggestionOverlayState extends ConsumerState<NoteSuggestionOverlay> {
  _NoteMatch? _match;

  @override
  void initState() {
    super.initState();
    widget.composer.selectionNotifier.addListener(_updateMatch);
    _updateMatch();
  }

  @override
  void didUpdateWidget(NoteSuggestionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.composer != oldWidget.composer) {
      oldWidget.composer.selectionNotifier.removeListener(_updateMatch);
      widget.composer.selectionNotifier.addListener(_updateMatch);
      _updateMatch();
    }
  }

  @override
  void dispose() {
    widget.composer.selectionNotifier.removeListener(_updateMatch);
    super.dispose();
  }

  void _updateMatch() {
    final selection = widget.composer.selection;
    if (selection == null || !selection.isCollapsed) {
      if (_match != null) setState(() => _match = null);
      return;
    }

    final position = selection.extent;
    final nodeId = position.nodeId;
    final node = widget.editor.document.getNodeById(nodeId);
    if (node is! TextNode) {
      if (_match != null) setState(() => _match = null);
      return;
    }

    final text = node.text.toPlainText();
    final caretOffset = (position.nodePosition as TextNodePosition).offset;
    if (caretOffset == 0) {
      if (_match != null) setState(() => _match = null);
      return;
    }

    final textBeforeCaret = text.substring(0, caretOffset);
    final match = RegExp(r'@([^\s@]*)$').firstMatch(textBeforeCaret);

    if (match == null) {
      if (_match != null) setState(() => _match = null);
      return;
    }

    setState(() {
      _match = _NoteMatch(
        query: match.group(1)!,
        nodeId: node.id,
        tagStart: match.start,
        tagEnd: caretOffset,
      );
    });
  }

  void _onNoteSelected(NoteModel note) {
    final match = _match;
    if (match == null) return;
    applyNoteSuggestion(
      editor: widget.editor,
      nodeId: match.nodeId,
      tagStartOffset: match.tagStart,
      tagEndOffset: match.tagEnd,
      note: note,
    );
  }

  @override
  Widget build(BuildContext context) {
    final match = _match;
    if (match == null) return const SizedBox.shrink();

    final suggestionsState = ref.watch(
      noteSuggestionsProvider((
        query: match.query,
        currentNoteId: widget.currentNoteId,
      )),
    );
    return suggestionsState.when(
      data: (suggestions) {
        if (suggestions.isEmpty) return const SizedBox.shrink();

        final chips = suggestions.take(10).map((note) {
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: AppChoiceChip(
              label: note.title,
              onTap: () => _onNoteSelected(note),
            ),
          );
        }).toList();

        return SizedBox(
          height: 44,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            itemCount: chips.length,
            itemBuilder: (_, i) => chips[i],
          ),
        );
      },
      loading: () => const SizedBox(height: 44),
      error: (error, stackTrace) => const SizedBox(
        height: 44,
        child: Center(child: Text('Não foi possível carregar sugestões')),
      ),
    );
  }
}

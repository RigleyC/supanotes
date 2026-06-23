import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/presentation/controllers/notes_providers.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_suggestion_handler.dart';

class NoteSuggestionOverlay extends ConsumerStatefulWidget {
  final Editor editor;
  final DocumentComposer composer;
  final String currentNoteId;
  final Future<void> Function() onPersist;

  const NoteSuggestionOverlay({
    super.key,
    required this.editor,
    required this.composer,
    required this.currentNoteId,
    required this.onPersist,
  });

  @override
  ConsumerState<NoteSuggestionOverlay> createState() => _NoteSuggestionOverlayState();
}

class _NoteMatch {
  final String query;
  final String nodeId;
  final int tagStart;
  final int tagEnd;
  const _NoteMatch({required this.query, required this.nodeId, required this.tagStart, required this.tagEnd});
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
      _match = _NoteMatch(query: match.group(1)!, nodeId: node.id, tagStart: match.start, tagEnd: caretOffset);
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
      onPersist: widget.onPersist,
    );
  }

  @override
  Widget build(BuildContext context) {
    final match = _match;
    if (match == null) return const SizedBox.shrink();

    final notesAsync = ref.watch(activeNotesProvider);
    return notesAsync.when(
      data: (notes) {
        final suggestions = notes
            .where((n) => n.id != widget.currentNoteId && n.title.toLowerCase().contains(match.query.toLowerCase()))
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        if (suggestions.isEmpty) return const SizedBox.shrink();

        final chips = suggestions.take(10).map((note) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                onTap: () => _onNoteSelected(note),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Text(
                    note.title,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ),
          );
        }).toList();

        return SizedBox(
          height: 44,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: chips.length,
            itemBuilder: (_, i) => chips[i],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

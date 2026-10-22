import 'package:flutter/foundation.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/selection_formatting.dart';
import 'package:super_editor/super_editor.dart';

/// Which row of the note toolbar is shown.
enum NoteToolbarMode { normal, contextual }

/// Everything the note toolbar shows, derived once from the document and the
/// selection. Equal values mean nothing visible changed, so the toolbar can
/// skip the rebuild.
@immutable
class NoteToolbarState {
  const NoteToolbarState({
    required this.mode,
    required this.blockType,
    required this.listType,
    required this.activeAttributions,
    required this.allTasks,
    required this.hasListOrTask,
    required this.hasTextSelection,
  });

  factory NoteToolbarState.from(
    Document document,
    DocumentSelection? selection,
  ) {
    final nodes = editorSelectionNodes(document, selection);
    final hasTextSelection = selection != null && !selection.isCollapsed;
    return NoteToolbarState(
      mode: _modeFor(document, selection),
      blockType: resolveSelectedBlockType(nodes),
      listType: _listTypeOf(nodes),
      activeAttributions: {
        if (hasTextSelection)
          for (final attribution in _inlineAttributions)
            if (hasAttributionInEditorSelection(
              document,
              selection,
              attribution,
            ))
              attribution,
      },
      allTasks: nodes.isNotEmpty && nodes.every((node) => node is TaskNode),
      hasListOrTask: nodes.any(
        (node) => node is ListItemNode || node is TaskNode,
      ),
      hasTextSelection: hasTextSelection,
    );
  }

  static const List<Attribution> _inlineAttributions = [
    boldAttribution,
    italicsAttribution,
    strikethroughAttribution,
  ];

  final NoteToolbarMode mode;

  /// Block format shared by every selected paragraph, if there is one.
  final Attribution? blockType;

  /// List type shared by every selected list item, if there is one.
  final ListItemType? listType;

  /// Inline formats (bold, italic, strikethrough) present in the selection.
  final Set<Attribution> activeAttributions;

  /// True when every selected node is a task.
  final bool allTasks;

  /// True when at least one selected node is a list item or a task.
  final bool hasListOrTask;

  /// True when the selection covers text, so inline formats can apply.
  final bool hasTextSelection;

  /// Contextual mode for a text selection, or a caret inside a list or task.
  static NoteToolbarMode _modeFor(
    Document document,
    DocumentSelection? selection,
  ) {
    if (selection == null) return NoteToolbarMode.normal;
    if (!selection.isCollapsed) return NoteToolbarMode.contextual;
    final node = document.getNodeById(selection.extent.nodeId);
    return node is ListItemNode || node is TaskNode
        ? NoteToolbarMode.contextual
        : NoteToolbarMode.normal;
  }

  static ListItemType? _listTypeOf(List<DocumentNode> nodes) {
    if (nodes.isEmpty || nodes.any((node) => node is! ListItemNode)) {
      return null;
    }
    final listTypes = nodes
        .cast<ListItemNode>()
        .map((node) => node.type)
        .toSet();
    return listTypes.length == 1 ? listTypes.single : null;
  }

  @override
  bool operator ==(Object other) {
    return other is NoteToolbarState &&
        other.mode == mode &&
        other.blockType == blockType &&
        other.listType == listType &&
        setEquals(other.activeAttributions, activeAttributions) &&
        other.allTasks == allTasks &&
        other.hasListOrTask == hasListOrTask &&
        other.hasTextSelection == hasTextSelection;
  }

  @override
  int get hashCode => Object.hash(
    mode,
    blockType,
    listType,
    Object.hashAllUnordered(activeAttributions),
    allTasks,
    hasListOrTask,
    hasTextSelection,
  );
}

/// Returns the common block attribution for a homogeneous paragraph set.
Attribution? resolveSelectedBlockType(Iterable<DocumentNode> nodes) {
  final paragraphs = nodes.whereType<ParagraphNode>().toList(growable: false);
  if (paragraphs.isEmpty || paragraphs.length != nodes.length) return null;

  final blockTypes = paragraphs
      .map((node) => node.getMetadataValue('blockType'))
      .whereType<Attribution>()
      .toSet();
  return blockTypes.length == 1 ? blockTypes.single : null;
}

import 'dart:math' as math;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_codec.dart';
import 'package:supanotes/features/notes/editor/document/note_blocks.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_divider_art.dart';
import 'package:uuid/uuid.dart';

/// Block formats the toolbar can apply to text blocks.
enum NoteBlockStyle {
  paragraph('paragraph'),
  header1('header1'),
  header2('header2'),
  header3('header3'),
  quote('quote'),
  bulletList('bulletList'),
  orderedList('orderedList'),
  task('task');

  const NoteBlockStyle(this.type);

  /// The synced block type.
  final String type;

  static NoteBlockStyle? ofType(String type) {
    for (final style in values) {
      if (style.type == type) return style;
    }
    return null;
  }
}

/// Inline formats the toolbar toggles.
abstract final class NoteInlineStyle {
  static const bold = 'bold';
  static const italic = 'italic';
  static const strikethrough = 'strikethrough';
  static const underline = 'underline';
  static const all = [bold, italic, strikethrough, underline];
}

const _nestableTypes = {'bulletList', 'orderedList', 'task'};
const _uuid = Uuid();

/// What the formatting controls show for the current selection. Equal values
/// mean nothing visible changed, so a toolbar can skip its rebuild.
@immutable
final class NoteFormatState {
  const NoteFormatState({
    this.hasSelection = false,
    this.hasTextSelection = false,
    this.blockStyle,
    this.inlineStyles = const {},
    this.hasListOrTask = false,
  });

  /// Reads the state of [editorState]'s selection.
  factory NoteFormatState.of(EditorState editorState) {
    final selection = editorState.selection;
    if (selection == null) return const NoteFormatState();
    final nodes = editorState
        .getNodesInSelection(selection)
        .where((node) => node.delta != null)
        .toList();
    final styles = {
      for (final node in nodes) NoteBlockStyle.ofType(_typeOf(node)),
    };
    final hasTextSelection = !selection.isCollapsed;
    return NoteFormatState(
      hasSelection: true,
      hasTextSelection: hasTextSelection,
      blockStyle: styles.length == 1 ? styles.single : null,
      inlineStyles: {
        for (final key in NoteInlineStyle.all)
          if (hasTextSelection
              ? nodes.allSatisfyInSelection(
                  selection,
                  (delta) => delta.everyAttributes(
                    (attributes) => attributes[key] == true,
                  ),
                )
              : editorState.toggledStyle[key] == true)
            key,
      },
      hasListOrTask: nodes.any(
        (node) => _nestableTypes.contains(_typeOf(node)),
      ),
    );
  }

  /// There is a caret or a selection in the note.
  final bool hasSelection;

  /// The selection covers text, so inline formats apply to it.
  final bool hasTextSelection;

  /// The format shared by every selected text block, if there is one.
  final NoteBlockStyle? blockStyle;

  /// Inline formats present on all of the selected text.
  final Set<String> inlineStyles;

  /// At least one selected block is a list item or a task (indentable).
  final bool hasListOrTask;

  /// Every selected text block is a task.
  bool get allTasks => blockStyle == NoteBlockStyle.task;

  @override
  bool operator ==(Object other) =>
      other is NoteFormatState &&
      other.hasSelection == hasSelection &&
      other.hasTextSelection == hasTextSelection &&
      other.blockStyle == blockStyle &&
      setEquals(other.inlineStyles, inlineStyles) &&
      other.hasListOrTask == hasListOrTask;

  @override
  int get hashCode => Object.hash(
    hasSelection,
    hasTextSelection,
    blockStyle,
    Object.hashAllUnordered(inlineStyles),
    hasListOrTask,
  );
}

String _typeOf(Node node) => switch (node.type) {
  HeadingBlockKeys.type =>
    'header${(node.attributes[HeadingBlockKeys.level] as int? ?? 1).clamp(1, 3)}',
  QuoteBlockKeys.type => 'quote',
  BulletedListBlockKeys.type => 'bulletList',
  NumberedListBlockKeys.type => 'orderedList',
  TodoListBlockKeys.type => 'task',
  ParagraphBlockKeys.type => 'paragraph',
  _ => node.type,
};

/// The result of a toolbar edit on the flat block list: the new blocks and,
/// optionally, the block that should receive the caret.
typedef _Rewrite = ({List<NoteBlock> blocks, String? caretBlockId});

/// Formatting and block commands for the note toolbar.
///
/// Block-level commands work on the synced model's flat block list, with the
/// same rules as before the editor switch (toggle off when every block has the
/// format, only lists and tasks keep an indent, ...), and rebuild just the
/// top-level blocks the selection touches in one undoable transaction. Reading
/// order is therefore always preserved, and the sync diff only sees the
/// blocks that really changed.
extension NoteFormatCommands on EditorState {
  static const _codec = NoteAppFlowyCodec();

  /// Toggles an inline format on the selection (or for the next typed text).
  Future<void> toggleNoteInlineStyle(String key) => toggleAttribute(key);

  /// Applies [style] to the selected text blocks, or turns them back into
  /// paragraphs when they all have it already.
  Future<void> toggleNoteBlockStyle(NoteBlockStyle style) =>
      _applyBlockStyle(style, toggle: true);

  /// Applies [style] to the selected text blocks (a choice among styles: the
  /// current one stays).
  Future<void> setNoteBlockStyle(NoteBlockStyle style) =>
      _applyBlockStyle(style, toggle: false);

  Future<void> _applyBlockStyle(NoteBlockStyle style, {required bool toggle}) =>
      _rewriteSelection((blocks, selected) {
        final targets = blocks
            .where((block) => selected.contains(block.id) && _isText(block))
            .toList();
        if (targets.isEmpty) return null;
        final clear =
            toggle &&
            style != NoteBlockStyle.paragraph &&
            targets.every((block) => block.type == style.type);
        final type = clear ? 'paragraph' : style.type;
        return (
          blocks: [
            for (final block in blocks)
              selected.contains(block.id) && _isText(block)
                  ? _convert(block, type)
                  : block,
          ],
          caretBlockId: null,
        );
      });

  /// Links the selected text to note [noteId].
  Future<void> linkSelectionToNote(String noteId) async {
    final current = selection;
    if (current == null || current.isCollapsed) return;
    await formatDelta(current, {AppFlowyRichTextKeys.href: 'note://$noteId'});
  }

  /// Indents the selected list items and tasks one level, when the block
  /// above can hold them.
  Future<void> indentNoteBlocks() => _rewriteSelection((blocks, selected) {
    final result = <NoteBlock>[];
    for (final block in blocks) {
      final previous = result.lastOrNull;
      final canIndent =
          selected.contains(block.id) &&
          _nestableTypes.contains(block.type) &&
          previous != null &&
          _nestableTypes.contains(previous.type) &&
          previous.indent >= block.indent;
      result.add(canIndent ? _withIndent(block, block.indent + 1) : block);
    }
    return (blocks: result, caretBlockId: null);
  }, includePrevious: true);

  /// Outdents the selected list items and tasks one level.
  Future<void> outdentNoteBlocks() => _rewriteSelection((blocks, selected) {
    return (
      blocks: [
        for (final block in blocks)
          selected.contains(block.id) && block.indent > 0
              ? _withIndent(block, block.indent - 1)
              : block,
      ],
      caretBlockId: null,
    );
  });

  /// Inserts a divider with a random illustration after the caret's block.
  Future<void> insertNoteDivider() => insertNoteBlockAtCaret(
    NoteBlock(
      id: _uuid.v4(),
      type: 'divider',
      metadata: {
        'dividerIndex': math.Random().nextInt(NoteDividerArt.count) + 1,
      },
    ),
  );

  /// Inserts [block] after the caret's block (or at the end when there is no
  /// caret) and puts the caret on the text block after it. An empty
  /// paragraph at the caret is replaced instead, like inserting into a blank
  /// line.
  Future<void> insertNoteBlockAtCaret(NoteBlock block) async {
    if (selection == null) {
      final last = document.root.children.lastOrNull;
      selection = last == null
          ? null
          : Selection.collapsed(Position(path: last.path));
    }
    await _rewriteSelection((blocks, selected) {
      final index = blocks.lastIndexWhere((b) => selected.contains(b.id));
      if (index < 0) return null;
      final current = blocks[index];
      final replaceBlank = current.type == 'paragraph' && current.text.isEmpty;
      final result = [...blocks];
      if (replaceBlank) {
        result[index] = block;
      } else {
        result.insert(index + 1, block);
      }
      final blockIndex = result.indexOf(block);
      // Keep a text block after the inserted one so typing can continue.
      if (blockIndex == result.length - 1 || !_isText(result[blockIndex + 1])) {
        result.insert(
          blockIndex + 1,
          NoteBlock(id: _uuid.v4(), type: 'paragraph'),
        );
      }
      return (blocks: result, caretBlockId: result[blockIndex + 1].id);
    }, includeNext: true);
  }

  /// Rebuilds the top-level blocks that the selection touches.
  Future<void> _rewriteSelection(
    _Rewrite? Function(List<NoteBlock> blocks, Set<String> selected) rewrite, {
    bool includePrevious = false,
    bool includeNext = false,
  }) async {
    final current = selection?.normalized;
    if (current == null) return;
    final range = _touchedRoots(
      current,
      includePrevious: includePrevious,
      includeNext: includeNext,
    );
    if (range == null) return;

    final reader = _BlockReader();
    for (final node in range.nodes) {
      reader.read(node, 0);
    }
    final selected = {
      for (final node in getNodesInSelection(current))
        if (reader.idOf[node] case final id?) id,
    };
    final result = rewrite(reader.blocks, selected);
    if (result == null || listEquals(result.blocks, reader.blocks)) return;

    final placement = _Placement(
      nodes: _codec.toDocument(result.blocks).root.children.toList(),
      first: range.first,
      idOf: reader.idOf,
    );
    final afterSelection = _selectionAfter(
      current,
      caretBlockId: result.caretBlockId,
      placement: placement,
    );
    final transaction = this.transaction
      ..insertNodes([range.first], placement.nodes)
      ..deleteNodes(range.nodes)
      ..afterSelection = afterSelection;
    await apply(transaction);
  }

  /// The top-level nodes [current] spans, widened by one on either side when
  /// asked, and the index of the first one.
  ({int first, List<Node> nodes})? _touchedRoots(
    Selection current, {
    required bool includePrevious,
    required bool includeNext,
  }) {
    final roots = document.root.children.toList();
    if (roots.isEmpty) return null;
    var first = current.start.path.first.clamp(0, roots.length - 1);
    var last = current.end.path.first.clamp(0, roots.length - 1);
    if (includePrevious && first > 0) first--;
    if (includeNext && last < roots.length - 1) last++;
    return (first: first, nodes: roots.sublist(first, last + 1));
  }

  /// The selection after a rewrite: a caret in [caretBlockId] when given,
  /// otherwise the previous selection moved along with its blocks.
  Selection? _selectionAfter(
    Selection current, {
    required String? caretBlockId,
    required _Placement placement,
  }) {
    final caretPath = placement.pathOf(caretBlockId);
    if (caretPath != null) {
      return Selection.collapsed(Position(path: caretPath));
    }
    final start = _movedPosition(current.start, placement);
    final end = _movedPosition(current.end, placement);
    return start != null && end != null
        ? Selection(start: start, end: end)
        : null;
  }

  /// [position] in the rebuilt blocks, or null when its block is gone.
  Position? _movedPosition(Position position, _Placement placement) {
    final node = getNodeAtPath(position.path);
    final path = placement.pathOf(node == null ? null : placement.idOf[node]);
    return path == null ? null : position.copyWith(path: path);
  }
}

/// Reads nodes and their children as flat blocks, remembering the block id
/// each node got. Nodes without an id, or with one already seen (a pasted
/// copy), get a fresh one.
final class _BlockReader {
  final idOf = <Node, String>{};
  final blocks = <NoteBlock>[];
  final _seen = <String>{};

  void read(Node node, int depth) {
    var id = node.attributes[NoteNodeKeys.blockId] as String?;
    if (id == null || !_seen.add(id)) {
      id = _uuid.v4();
      _seen.add(id);
    }
    idOf[node] = id;
    blocks.add(NoteFormatCommands._codec.toBlock(node, id: id, depth: depth));
    for (final child in node.children) {
      read(child, depth + 1);
    }
  }
}

/// Where rebuilt blocks land: [nodes] replace the top-level nodes from index
/// [first]; [idOf] maps the replaced nodes to their block ids.
final class _Placement {
  const _Placement({
    required this.nodes,
    required this.first,
    required this.idOf,
  });

  final List<Node> nodes;
  final int first;
  final Map<Node, String> idOf;

  /// The document path block [id] will have, if it is among [nodes].
  Path? pathOf(String? id) {
    if (id == null) return null;
    for (var i = 0; i < nodes.length; i++) {
      final found = _find(nodes[i], id);
      if (found != null) {
        return [first + i, ...found.path.skip(1)];
      }
    }
    return null;
  }
}

Node? _find(Node node, String id) {
  if (node.attributes[NoteNodeKeys.blockId] == id) return node;
  for (final child in node.children) {
    final found = _find(child, id);
    if (found != null) return found;
  }
  return null;
}

bool _isText(NoteBlock block) => NoteBlockStyle.ofType(block.type) != null;

NoteBlock _withIndent(NoteBlock block, int indent) {
  final metadata = Map<String, dynamic>.from(block.metadata);
  if (indent > 0) {
    metadata['indent'] = indent;
  } else {
    metadata.remove('indent');
  }
  return block.copyWith(metadata: metadata);
}

/// [block] as a block of [type], keeping its text and identity.
NoteBlock _convert(NoteBlock block, String type) {
  if (block.type == type) return block;
  final keepsIndent = _nestableTypes.contains(type);
  final metadata = <String, dynamic>{
    // A task's schedule, reminder and completions only mean something on a
    // task; other blocks carry no metadata besides their indent.
    if (block.type == 'task' && type == 'task') ...block.metadata,
    if (keepsIndent && block.indent > 0) 'indent': block.indent,
  };
  return block.copyWith(type: type, metadata: metadata);
}

/// Typing `---` (or `—-` after the iOS smart dash) on an empty line turns it
/// into a divider with a random illustration.
final noteDividerShortcut = CharacterShortcutEvent(
  key: 'convert minuses to a note divider',
  character: '-',
  handler: (editorState) async {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) return false;
    final node = editorState.getNodeAtPath(selection.end.path);
    final text = node?.delta?.toPlainText();
    if (node == null || (text != '--' && text != '—')) return false;
    final transaction = editorState.transaction
      ..updateNode(node, {'delta': Delta().toJson()});
    await editorState.apply(transaction, withUpdateSelection: false);
    editorState.selection = Selection.collapsed(
      Position(path: node.path),
    );
    await editorState.insertNoteDivider();
    return true;
  },
);

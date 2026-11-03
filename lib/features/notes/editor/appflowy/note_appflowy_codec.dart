import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:supanotes/features/notes/editor/document/note_blocks.dart';
import 'package:uuid/uuid.dart';

/// Node types for SupaNotes blocks that have no AppFlowy counterpart.
abstract final class NoteNodeTypes {
  static const attachment = 'note_attachment';
  static const richLink = 'note_rich_link';
}

/// Node attribute keys owned by SupaNotes.
abstract final class NoteNodeKeys {
  /// Stable block identity. AppFlowy regenerates `Node.id` whenever it copies
  /// a node (indent, type conversion), but the block id is a task's identity
  /// for reminders, completions and deep links, so it lives in an attribute
  /// that copies carry along.
  static const blockId = 'blockId';

  /// Block metadata other than completion and indentation, which AppFlowy
  /// represents as the `checked` attribute and as nesting.
  static const metadata = 'noteMeta';
}

/// Inline attributes the synced document stores; editor-only styles such as
/// inline code or colors (from paste or shortcuts) are dropped.
///
/// Italic is stored as `italics`, the name every existing note and older app
/// version uses; AppFlowy calls it `italic`.
const _storedAttributes = {
  'bold',
  'italics',
  'strikethrough',
  'underline',
  'link',
};

/// Stored attribute name -> AppFlowy attribute name, where they differ.
const _editorNames = {'link': 'href', 'italics': 'italic', 'italic': 'italic'};

/// AppFlowy attribute name -> stored attribute name, where they differ.
const _storedNames = {'href': 'link', 'italic': 'italics'};

const _nestableTypes = {
  BulletedListBlockKeys.type,
  NumberedListBlockKeys.type,
  TodoListBlockKeys.type,
};

/// Converts between the synced block list and AppFlowy's document tree.
///
/// The synced model is a flat list where list items and tasks carry an
/// `indent`; AppFlowy nests indented list items as children. Everything else
/// maps one block to one node with the same identity.
final class NoteAppFlowyCodec {
  const NoteAppFlowyCodec();

  static const _uuid = Uuid();

  Document toDocument(List<NoteBlock> blocks) {
    final root = Node(type: 'page');
    // stack[d] = last node placed at depth d.
    final stack = <Node>[];
    for (final block in blocks) {
      final node = toNode(block);
      var depth = _nestableTypes.contains(node.type) ? block.indent : 0;
      if (depth > stack.length) depth = stack.length;
      while (depth > 0 && !_nestableTypes.contains(stack[depth - 1].type)) {
        depth--;
      }
      final parent = depth == 0 ? root : stack[depth - 1];
      parent.insert(node);
      stack
        ..length = depth
        ..add(node);
    }
    if (root.children.isEmpty) root.insert(paragraphNode());
    return Document(root: root);
  }

  Node toNode(NoteBlock block) {
    final metadata = Map<String, dynamic>.from(block.metadata)
      ..remove('indent')
      ..remove('isCompleted');
    final attributes = <String, dynamic>{
      NoteNodeKeys.blockId: block.id,
      if (metadata.isNotEmpty) NoteNodeKeys.metadata: metadata,
    };
    final delta = {'delta': _toEditorDelta(block.delta)};
    switch (block.type) {
      case 'header1' || 'header2' || 'header3':
        return Node(
          type: HeadingBlockKeys.type,
          attributes: {
            ...attributes,
            ...delta,
            HeadingBlockKeys.level: int.parse(block.type.substring(6)),
          },
        );
      case 'quote':
        return Node(
          type: QuoteBlockKeys.type,
          attributes: {...attributes, ...delta},
        );
      case 'bulletList':
        return Node(
          type: BulletedListBlockKeys.type,
          attributes: {...attributes, ...delta},
        );
      case 'orderedList':
        return Node(
          type: NumberedListBlockKeys.type,
          attributes: {...attributes, ...delta},
        );
      case 'task':
        return Node(
          type: TodoListBlockKeys.type,
          attributes: {
            ...attributes,
            ...delta,
            TodoListBlockKeys.checked:
                block.metadata['isCompleted'] as bool? ?? false,
          },
        );
      case 'divider':
        return Node(type: DividerBlockKeys.type, attributes: attributes);
      case 'attachment':
        return Node(type: NoteNodeTypes.attachment, attributes: attributes);
      case 'rich_link':
        return Node(type: NoteNodeTypes.richLink, attributes: attributes);
      default:
        return Node(
          type: ParagraphBlockKeys.type,
          attributes: {...attributes, ...delta},
        );
    }
  }

  /// Flattens the editor document into synced blocks, in reading order.
  ///
  /// Nodes created by the editor itself (Enter, paste) have no block id yet,
  /// and a pasted copy of a block arrives with a duplicate id. Both get the
  /// id returned by [idFor] (a fresh UUID by default); the caller can stamp
  /// it into the node so the identity stays stable.
  List<NoteBlock> toBlocks(
    Document document, {
    String Function(Node node)? idFor,
  }) {
    final blocks = <NoteBlock>[];
    final seen = <String>{};
    void visit(Node node, int depth) {
      var id = node.attributes[NoteNodeKeys.blockId] as String?;
      if (id == null || !seen.add(id)) {
        id = idFor?.call(node) ?? _uuid.v4();
        seen.add(id);
      }
      blocks.add(toBlock(node, id: id, depth: depth));
      for (final child in node.children) {
        visit(child, depth + 1);
      }
    }

    for (final node in document.root.children) {
      visit(node, 0);
    }
    return blocks;
  }

  /// Converts one node; [depth] is its nesting level in the editor tree.
  NoteBlock toBlock(Node node, {required String id, required int depth}) {
    final metadata = Map<String, dynamic>.from(
      node.attributes[NoteNodeKeys.metadata] as Map? ?? const {},
    );
    final isNestable = _nestableTypes.contains(node.type);
    if (isNestable && depth > 0) metadata['indent'] = depth;
    final delta = _fromEditorDelta(node.attributes['delta']);
    switch (node.type) {
      case HeadingBlockKeys.type:
        final level = (node.attributes[HeadingBlockKeys.level] as int? ?? 1)
            .clamp(1, 3);
        return NoteBlock(
          id: id,
          type: 'header$level',
          delta: delta,
          metadata: metadata,
        );
      case QuoteBlockKeys.type:
        return NoteBlock(
          id: id,
          type: 'quote',
          delta: delta,
          metadata: metadata,
        );
      case BulletedListBlockKeys.type:
        return NoteBlock(
          id: id,
          type: 'bulletList',
          delta: delta,
          metadata: metadata,
        );
      case NumberedListBlockKeys.type:
        return NoteBlock(
          id: id,
          type: 'orderedList',
          delta: delta,
          metadata: metadata,
        );
      case TodoListBlockKeys.type:
        metadata['isCompleted'] =
            node.attributes[TodoListBlockKeys.checked] as bool? ?? false;
        return NoteBlock(
          id: id,
          type: 'task',
          delta: delta,
          metadata: metadata,
        );
      case DividerBlockKeys.type:
        return NoteBlock(id: id, type: 'divider', metadata: metadata);
      case NoteNodeTypes.attachment:
        return NoteBlock(id: id, type: 'attachment', metadata: metadata);
      case NoteNodeTypes.richLink:
        return NoteBlock(id: id, type: 'rich_link', metadata: metadata);
      default:
        return NoteBlock(
          id: id,
          type: 'paragraph',
          delta: delta,
          metadata: metadata,
        );
    }
  }

  static List<Map<String, dynamic>> _toEditorDelta(
    List<Map<String, dynamic>> ops,
  ) => [for (final op in ops) _renameAttributes(op, _editorNames)];

  static List<Map<String, dynamic>> _fromEditorDelta(Object? raw) {
    if (raw is! List) return const [];
    final ops = <Map<String, dynamic>>[];
    for (final op in raw) {
      if (op is! Map || op['insert'] is! String || op['insert'] == '') continue;
      _appendStoredOp(ops, Map<String, dynamic>.from(op));
    }
    return ops;
  }

  /// Adds editor text [op] to [ops] in the stored form, merged into the last
  /// op when their attributes match.
  static void _appendStoredOp(
    List<Map<String, dynamic>> ops,
    Map<String, dynamic> op,
  ) {
    final renamed = _renameAttributes(op, _storedNames);
    final cleaned = _storedAttributesOf(renamed['attributes']);
    final text = renamed['insert'] as String;
    if (ops.isNotEmpty &&
        _sameAttributes(
          ops.last['attributes'] as Map<String, dynamic>?,
          cleaned,
        )) {
      ops.last = {...ops.last, 'insert': '${ops.last['insert']}$text'};
    } else {
      ops.add({'insert': text, if (cleaned.isNotEmpty) 'attributes': cleaned});
    }
  }

  /// The stored attributes among [attributes].
  static Map<String, dynamic> _storedAttributesOf(Object? attributes) {
    if (attributes is! Map) return const <String, dynamic>{};
    // Toggling a style off can leave `{bold: null}` behind; it means "no
    // attribute", and keeping it would make equal text look different.
    return {
      for (final entry in attributes.entries)
        if (entry.value != null && _storedAttributes.contains(entry.key))
          entry.key as String: entry.value,
    };
  }

  static bool _sameAttributes(Map<String, dynamic>? a, Map<String, dynamic> b) {
    final left = a ?? const {};
    if (left.length != b.length) return false;
    for (final entry in left.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  static Map<String, dynamic> _renameAttributes(
    Map<String, dynamic> op,
    Map<String, String> names,
  ) {
    final attributes = op['attributes'];
    if (attributes is! Map || !attributes.keys.any(names.containsKey)) {
      return op;
    }
    return {
      ...op,
      'attributes': <String, dynamic>{
        for (final entry in attributes.entries)
          names[entry.key] ?? entry.key as String: entry.value,
      },
    };
  }
}

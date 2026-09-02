import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';
import 'package:super_editor/super_editor.dart';

/// Rebuilds document nodes while preserving the node-specific fields that are
/// not represented by an operation payload.
///
/// Both the live editor applier and the durable effective-document projector
/// use these transformations so their node shapes cannot drift apart.
final class DocumentNodeTransforms {
  /// Creates transformations that normalize block-type attributions with
  /// the supplied codec.
  const DocumentNodeTransforms(this._codec);

  final NoteDocumentCodec _codec;

  /// Returns [node] with [text], retaining its block-specific metadata.
  DocumentNode withText(TextNode node, AttributedText text) {
    if (node is TaskNode) {
      return TaskNode(
        id: node.id,
        text: text,
        isComplete: node.isComplete,
        indent: node.indent,
        metadata: Map<String, dynamic>.from(node.metadata),
      );
    }
    if (node is ListItemNode) {
      return ListItemNode(
        id: node.id,
        itemType: node.type,
        text: text,
        indent: node.indent,
        metadata: Map<String, dynamic>.from(node.metadata),
      );
    }
    if (node is ParagraphNode) {
      return ParagraphNode(
        id: node.id,
        text: text,
        indent: node.indent,
        metadata: Map<String, dynamic>.from(node.metadata),
      );
    }
    return ParagraphNode(id: node.id, text: text);
  }

  /// Returns [node] after applying nullable metadata [updates].
  DocumentNode withMetadata(
    DocumentNode node,
    Map<String, dynamic> updates,
  ) {
    final metadata = _mergeMetadata(node.metadata, updates);
    _normalizeBlockType(metadata);

    if (node is TaskNode) {
      return TaskNode(
        id: node.id,
        text: node.text,
        isComplete: updates.containsKey('isCompleted')
            ? updates['isCompleted'] as bool
            : node.isComplete,
        indent: _updatedIndent(node.indent, updates),
        metadata: metadata,
      );
    }
    if (node is ParagraphNode) {
      return ParagraphNode(
        id: node.id,
        text: node.text,
        indent: _updatedIndent(node.indent, updates),
        metadata: metadata,
      );
    }
    if (node is ListItemNode) {
      return ListItemNode(
        id: node.id,
        itemType: node.type,
        text: node.text,
        indent: _updatedIndent(node.indent, updates),
        metadata: metadata,
      );
    }
    return node;
  }

  Map<String, dynamic> _mergeMetadata(
    Map<String, dynamic> current,
    Map<String, dynamic> updates,
  ) {
    final merged = Map<String, dynamic>.from(current);
    for (final entry in updates.entries) {
      if (entry.value == null) {
        merged.remove(entry.key);
      } else {
        merged[entry.key] = entry.value;
      }
    }
    return merged;
  }

  void _normalizeBlockType(Map<String, dynamic> metadata) {
    if (!metadata.containsKey('blockType')) return;

    final rawBlockType = metadata['blockType'];
    if (rawBlockType is String) {
      final attribution = _codec.attributionFromName(rawBlockType);
      if (attribution != null) {
        metadata['blockType'] = attribution;
      } else {
        metadata.remove('blockType');
      }
    } else if (rawBlockType == null) {
      metadata.remove('blockType');
    }
  }

  int _updatedIndent(int currentIndent, Map<String, dynamic> updates) {
    return updates.containsKey('indent')
        ? updates['indent'] as int? ?? 0
        : currentIndent;
  }
}

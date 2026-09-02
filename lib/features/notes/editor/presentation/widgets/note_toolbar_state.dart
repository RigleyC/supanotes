import 'package:super_editor/super_editor.dart';

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

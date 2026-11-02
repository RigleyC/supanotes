library;

import 'package:flutter/material.dart';
import 'package:block_editor/block_editor.dart';

/// Maps a [BlockNode] to its block widget via [BlockRegistry].
///
/// [BlockRenderer] is stateless. It delegates all type resolution to the
/// singleton [BlockRegistry]. Unknown block types render as [UnknownBlock]
/// rather than throwing.
///
/// The caller is responsible for supplying the correct [number] ordinal for
/// numbered list items. [BlockRenderer] never derives position from context.
class BlockRenderer extends StatelessWidget {
  /// Creates a [BlockRenderer] for [node].
  ///
  /// [onEvent] is forwarded to the rendered block widget.
  ///
  /// [number] is the visible ordinal for numbered list items. Ignored for
  /// all other block types. Injected into [node] attributes transiently
  /// before registry delegation so NumberedListPlugin can read it.
  ///
  /// [selection] is forwarded to the rendered block widget for highlight
  /// painting.
  const BlockRenderer({
    super.key,
    required this.node,
    required this.onEvent,
    this.number = 1,
    this.selection = EditorSelection.none,
  });

  /// The block node to render.
  final BlockNode node;

  /// Called when the user interacts with the rendered block.
  final void Function(BlockEvent) onEvent;

  /// The visible ordinal for numbered list items.
  final int number;

  /// The current editor selection, forwarded to the rendered block widget.
  final EditorSelection selection;

  @override
  Widget build(BuildContext context) {
    final resolvedNode =
        node.type == BlockTypes.numberedList &&
            !node.attributes.containsKey('number')
        ? node.copyWith(attributes: {...node.attributes, 'number': number})
        : node;
    return BlockRegistry.instance.build(resolvedNode, selection, onEvent);
  }
}

/// Rendered in place of any block whose type is not registered.
///
/// Displays the unrecognised type string so documents containing unknown
/// block types degrade visibly rather than crashing.
class UnknownBlock extends StatelessWidget {
  /// Creates an [UnknownBlock] for the unrecognised [type].
  const UnknownBlock({super.key, required this.blockId, required this.type});

  /// The id of the block this widget represents.
  final String blockId;

  /// The unrecognised block type string.
  final String type;

  @override
  Widget build(BuildContext context) {
    return Text(
      '[unknown block: $type]',
      style: const TextStyle(color: Color(0xFFFF0000), fontFamily: 'monospace'),
    );
  }
}

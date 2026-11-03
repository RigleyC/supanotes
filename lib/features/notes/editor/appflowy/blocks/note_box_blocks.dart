import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supanotes/features/notes/attachments/domain/attachment_delivery.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_codec.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/attachment_renderers.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/document_attachment_widget.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_divider_art.dart';

/// Builds the visual content of a non-text block.
typedef NoteBoxContentBuilder = Widget Function(
  BuildContext context,
  Node node,
  EditorState editorState,
);

Map<String, dynamic> _metadataOf(Node node) => Map<String, dynamic>.from(
  node.attributes[NoteNodeKeys.metadata] as Map? ?? const {},
);

/// The hand-drawn divider, chosen by the block's `dividerIndex`.
NoteBoxBlockComponentBuilder noteDividerBlockBuilder() =>
    NoteBoxBlockComponentBuilder(
      content: (context, node, _) => IgnorePointer(
        child: NoteDividerArt(
          dividerIndex: _metadataOf(node)['dividerIndex'] as int?,
        ),
      ),
    );

/// An uploaded file or image.
NoteBoxBlockComponentBuilder noteAttachmentBlockBuilder({
  required bool collapseImages,
  required bool readOnly,
  AttachmentDelivery? attachmentDelivery,
}) => NoteBoxBlockComponentBuilder(
  content: (context, node, editorState) {
    final metadata = _metadataOf(node);
    final storedId = metadata['attachmentId'];
    final attachmentId = storedId is String && storedId.isNotEmpty
        ? storedId
        : node.attributes[NoteNodeKeys.blockId] as String? ?? node.id;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DocumentAttachmentContent(
        attachmentId: attachmentId,
        collapseImages: collapseImages,
        deliveryPreference:
            attachmentDelivery?.preference ??
            AttachmentDeliveryPreference.localFirst,
        attachmentDelivery: attachmentDelivery,
        fallbackAttachment: attachmentDelivery == null
            ? null
            : AttachmentReference(
                id: attachmentId,
                fileName: metadata['filename'] as String? ?? 'Anexo',
                downloadUrl: metadata['url'] as String?,
              ),
        onDelete: readOnly
            ? null
            : () =>
                  editorState.apply(editorState.transaction..deleteNode(node)),
      ),
    );
  },
);

/// A link preview card.
NoteBoxBlockComponentBuilder noteRichLinkBlockBuilder({
  bool allowInternalNoteLinks = true,
}) => NoteBoxBlockComponentBuilder(
  content: (context, node, _) {
    final metadata = _metadataOf(node);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: RichLinkCard(
        url: metadata['url'] as String?,
        title: metadata['title'] as String?,
        description: metadata['description'] as String?,
        imageUrl: metadata['imageUrl'] as String?,
        domain: metadata['domain'] as String?,
        siteName: metadata['siteName'] as String?,
        allowInternalNoteLinks: allowInternalNoteLinks,
      ),
    );
  },
);

/// A block without text that is selected as a whole, like AppFlowy's divider.
final class NoteBoxBlockComponentBuilder extends BlockComponentBuilder {
  NoteBoxBlockComponentBuilder({required this.content, super.configuration});

  /// Draws the block.
  final NoteBoxContentBuilder content;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return NoteBoxBlockComponent(
      key: node.key,
      node: node,
      configuration: configuration,
      content: content,
    );
  }

  @override
  BlockComponentValidate get validate =>
      (node) => node.children.isEmpty;
}

/// See [NoteBoxBlockComponentBuilder].
class NoteBoxBlockComponent extends BlockComponentStatefulWidget {
  /// Creates the block widget for [node].
  const NoteBoxBlockComponent({
    required super.node,
    required this.content,
    super.key,
    super.configuration = const BlockComponentConfiguration(),
  });

  /// Draws the block.
  final NoteBoxContentBuilder content;

  @override
  State<NoteBoxBlockComponent> createState() => _NoteBoxBlockState();
}

class _NoteBoxBlockState extends State<NoteBoxBlockComponent>
    with SelectableMixin, BlockComponentConfigurable {
  final _boxKey = GlobalKey();

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  @override
  Widget build(BuildContext context) {
    final editorState = context.read<EditorState>();
    Widget child = Padding(
      key: _boxKey,
      padding: padding,
      child: widget.content(context, node, editorState),
    );
    child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      cursorColor: editorState.editorStyle.cursorColor,
      selectionColor: editorState.editorStyle.selectionColor,
      supportTypes: const [
        BlockSelectionType.block,
        BlockSelectionType.cursor,
        BlockSelectionType.selection,
      ],
      child: child,
    );
    return Padding(padding: margin, child: child);
  }

  @override
  Position start() => Position(path: node.path);

  @override
  Position end() => Position(path: node.path, offset: 1);

  @override
  Position getPositionInOffset(Offset start) => end();

  @override
  bool get shouldCursorBlink => false;

  @override
  CursorStyle get cursorStyle => CursorStyle.cover;

  @override
  Rect getBlockRect({bool shiftWithBaseOffset = false}) =>
      getRectsInSelection(Selection.invalid()).first;

  @override
  Rect? getCursorRectInPosition(
    Position position, {
    bool shiftWithBaseOffset = false,
  }) {
    if (_renderBox == null) return null;
    return getRectsInSelection(
      Selection.collapsed(position),
      shiftWithBaseOffset: shiftWithBaseOffset,
    ).firstOrNull;
  }

  @override
  List<Rect> getRectsInSelection(
    Selection selection, {
    bool shiftWithBaseOffset = false,
  }) {
    final parentBox = _renderBox;
    if (parentBox == null) return [];
    final box = _boxKey.currentContext?.findRenderObject();
    if (box is RenderBox) {
      return [
        (shiftWithBaseOffset
                ? box.localToGlobal(Offset.zero, ancestor: parentBox)
                : Offset.zero) &
            box.size,
      ];
    }
    return [Offset.zero & parentBox.size];
  }

  @override
  Selection getSelectionInRange(Offset start, Offset end) =>
      Selection.single(path: node.path, startOffset: 0, endOffset: 1);

  @override
  Offset localToGlobal(Offset offset, {bool shiftWithBaseOffset = false}) =>
      _renderBox!.localToGlobal(offset);

  @override
  TextDirection textDirection() => TextDirection.ltr;
}

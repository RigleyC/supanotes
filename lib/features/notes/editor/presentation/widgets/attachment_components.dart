import 'package:flutter/material.dart';
import 'package:supanotes/features/notes/attachments/domain/attachment_delivery.dart';
import 'package:supanotes/features/notes/editor/document/attachment_nodes.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/attachment_renderers.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/document_attachment_widget.dart';
import 'package:super_editor/super_editor.dart';

class AttachmentComponentBuilder implements ComponentBuilder {
  const AttachmentComponentBuilder({
    required this.editor,
    required this.collapseImages,
    this.readOnly = false,
    this.allowInternalNoteLinks = true,
    this.attachmentDelivery,
  });

  final Editor editor;
  final bool collapseImages;
  final bool readOnly;
  final bool allowInternalNoteLinks;
  final AttachmentDelivery? attachmentDelivery;

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is! AttachmentNode) return null;
    return _AttachmentViewModel(
      nodeId: node.id,
      attachmentId:
          node is DocumentAttachmentNode &&
              node.metadata['attachmentId'] is String &&
              (node.metadata['attachmentId'] as String).isNotEmpty
          ? node.metadata['attachmentId'] as String
          : node.id,
      node: node,
      createdAt: node.metadata[NodeMetadata.createdAt] as DateTime?,
      collapseImages: collapseImages,
      allowInternalNoteLinks: allowInternalNoteLinks,
      fallbackAttachment:
          node is DocumentAttachmentNode && attachmentDelivery != null
          ? AttachmentReference(
              id:
                  node.metadata['attachmentId'] is String &&
                      (node.metadata['attachmentId'] as String).isNotEmpty
                  ? node.metadata['attachmentId'] as String
                  : node.id,
              fileName: node.metadata['filename'] is String
                  ? node.metadata['filename'] as String
                  : 'Anexo',
            )
          : null,
      attachmentDelivery: attachmentDelivery,
      attachmentDeliveryPreference:
          attachmentDelivery?.preference ??
          AttachmentDeliveryPreference.localFirst,
      onDelete: readOnly
          ? null
          : () {
              editor.execute([DeleteNodeRequest(nodeId: node.id)]);
            },
    );
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext context,
    SingleColumnLayoutComponentViewModel viewModel,
  ) {
    if (viewModel is! _AttachmentViewModel) return null;
    return switch (viewModel.node) {
      final DocumentAttachmentNode n => DocumentAttachmentWidget(
        componentKey: context.componentKey,
        nodeId: n.id,
        attachmentId: viewModel.attachmentId,
        selection:
            viewModel.selection?.nodeSelection
                as UpstreamDownstreamNodeSelection?,
        selectionColor: viewModel.selectionColor,
        onDelete: viewModel.onDelete,
        collapseImages: viewModel.collapseImages,
        fallbackAttachment: viewModel.fallbackAttachment,
        deliveryPreference: viewModel.attachmentDeliveryPreference,
        attachmentDelivery: viewModel.attachmentDelivery,
      ),
      final RichLinkNode n => AttachmentRichLinkCard(
        componentKey: context.componentKey,
        node: n,
        selection:
            viewModel.selection?.nodeSelection
                as UpstreamDownstreamNodeSelection?,
        selectionColor: viewModel.selectionColor,
        allowInternalNoteLinks: viewModel.allowInternalNoteLinks,
      ),
      _ => null,
    };
  }
}

class _AttachmentViewModel extends SingleColumnLayoutComponentViewModel
    with SelectionAwareViewModelMixin {
  _AttachmentViewModel({
    required super.nodeId,
    required this.attachmentId,
    required this.node,
    required this.onDelete,
    required this.collapseImages,
    required this.allowInternalNoteLinks,
    required this.fallbackAttachment,
    required this.attachmentDeliveryPreference,
    required this.attachmentDelivery,
    super.createdAt,
    super.padding = EdgeInsets.zero,
    DocumentNodeSelection? selection,
    Color selectionColor = Colors.transparent,
  }) {
    super.selection = selection;
    super.selectionColor = selectionColor;
  }

  final AttachmentNode node;
  final String attachmentId;
  final VoidCallback? onDelete;
  final bool collapseImages;
  final bool allowInternalNoteLinks;
  final AttachmentReference? fallbackAttachment;
  final AttachmentDeliveryPreference attachmentDeliveryPreference;
  final AttachmentDelivery? attachmentDelivery;

  @override
  _AttachmentViewModel copy() => _AttachmentViewModel(
    nodeId: nodeId,
    attachmentId: attachmentId,
    node: node,
    onDelete: onDelete,
    collapseImages: collapseImages,
    allowInternalNoteLinks: allowInternalNoteLinks,
    fallbackAttachment: fallbackAttachment,
    attachmentDeliveryPreference: attachmentDeliveryPreference,
    attachmentDelivery: attachmentDelivery,
    selection: selection,
    selectionColor: selectionColor,
  );

  @override
  bool operator ==(Object other) =>
      other is _AttachmentViewModel &&
      other.node.id == node.id &&
      other.attachmentId == attachmentId &&
      other.collapseImages == collapseImages &&
      other.allowInternalNoteLinks == allowInternalNoteLinks &&
      other.fallbackAttachment == fallbackAttachment &&
      other.attachmentDeliveryPreference == attachmentDeliveryPreference &&
      other.attachmentDelivery == attachmentDelivery;

  @override
  int get hashCode => Object.hash(
    node.id,
    attachmentId,
    collapseImages,
    allowInternalNoteLinks,
    fallbackAttachment,
    attachmentDeliveryPreference,
    attachmentDelivery,
  );
}

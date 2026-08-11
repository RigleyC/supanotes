import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/editor/document/attachment_nodes.dart';
import 'package:supanotes/features/notes/attachments/domain/attachment_delivery.dart';
import 'attachment_renderers.dart';
import 'document_attachment_widget.dart';

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
      node: node,
      createdAt: node.metadata[NodeMetadata.createdAt],
      collapseImages: collapseImages,
      allowInternalNoteLinks: allowInternalNoteLinks,
      fallbackAttachmentUrl: node is DocumentAttachmentNode
          ? attachmentDelivery
                ?.urlFor(
                  node.metadata['attachmentId'] is String &&
                          (node.metadata['attachmentId'] as String).isNotEmpty
                      ? node.metadata['attachmentId'] as String
                      : node.id,
                )
                ?.toString()
          : null,
      fallbackAttachmentName:
          node is DocumentAttachmentNode && node.metadata['filename'] is String
          ? node.metadata['filename'] as String
          : null,
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
      DocumentAttachmentNode n => DocumentAttachmentWidget(
        componentKey: context.componentKey,
        nodeId: n.id,
        selection:
            viewModel.selection?.nodeSelection
                as UpstreamDownstreamNodeSelection?,
        selectionColor: viewModel.selectionColor,
        onDelete: viewModel.onDelete,
        collapseImages: viewModel.collapseImages,
        fallbackUrl: viewModel.fallbackAttachmentUrl,
        fallbackFileName: viewModel.fallbackAttachmentName,
      ),
      RichLinkNode n => AttachmentRichLinkCard(
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
    required this.node,
    required this.onDelete,
    required this.collapseImages,
    required this.allowInternalNoteLinks,
    required this.fallbackAttachmentUrl,
    required this.fallbackAttachmentName,
    super.createdAt,
    super.padding = EdgeInsets.zero,
    DocumentNodeSelection? selection,
    Color selectionColor = Colors.transparent,
  }) {
    super.selection = selection;
    super.selectionColor = selectionColor;
  }

  final AttachmentNode node;
  final VoidCallback? onDelete;
  final bool collapseImages;
  final bool allowInternalNoteLinks;
  final String? fallbackAttachmentUrl;
  final String? fallbackAttachmentName;

  @override
  _AttachmentViewModel copy() => _AttachmentViewModel(
    nodeId: nodeId,
    node: node,
    onDelete: onDelete,
    collapseImages: collapseImages,
    allowInternalNoteLinks: allowInternalNoteLinks,
    fallbackAttachmentUrl: fallbackAttachmentUrl,
    fallbackAttachmentName: fallbackAttachmentName,
    selection: selection,
    selectionColor: selectionColor,
  );

  @override
  bool operator ==(Object other) =>
      other is _AttachmentViewModel && other.node.id == node.id;

  @override
  int get hashCode => node.id.hashCode;
}

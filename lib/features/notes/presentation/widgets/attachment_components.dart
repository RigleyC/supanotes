import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import '../../domain/attachment_nodes.dart';
import 'attachment_renderers.dart';
import 'document_attachment_widget.dart';

class AttachmentComponentBuilder implements ComponentBuilder {
  const AttachmentComponentBuilder({
    required this.editor,
    required this.collapseImages,
  });

  final Editor editor;
  final bool collapseImages;

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
      onDelete: () {
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
      ),
      RichLinkNode n => AttachmentRichLinkCard(
        componentKey: context.componentKey,
        node: n,
        selection:
            viewModel.selection?.nodeSelection
                as UpstreamDownstreamNodeSelection?,
        selectionColor: viewModel.selectionColor,
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
    super.createdAt,
    super.padding = EdgeInsets.zero,
    DocumentNodeSelection? selection,
    Color selectionColor = Colors.transparent,
  }) {
    super.selection = selection;
    super.selectionColor = selectionColor;
  }

  final AttachmentNode node;
  final VoidCallback onDelete;
  final bool collapseImages;

  @override
  _AttachmentViewModel copy() => _AttachmentViewModel(
    nodeId: nodeId,
    node: node,
    onDelete: onDelete,
    collapseImages: collapseImages,
    selection: selection,
    selectionColor: selectionColor,
  );

  @override
  bool operator ==(Object other) =>
      other is _AttachmentViewModel && other.node.id == node.id;

  @override
  int get hashCode => node.id.hashCode;
}

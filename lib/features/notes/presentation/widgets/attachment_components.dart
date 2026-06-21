import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/attachment_nodes.dart';

class AttachmentComponentBuilder implements ComponentBuilder {
  const AttachmentComponentBuilder({
    required this.editor,
    required this.collapseImages,
  });

  final Editor editor;
  final bool collapseImages;

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
      Document document, DocumentNode node) {
    if (node is! AttachmentNode) return null;
    return _AttachmentViewModel(
      nodeId: node.id,
      node: node,
      createdAt: node.metadata[NodeMetadata.createdAt],
      collapseImages: collapseImages,
      onDelete: () {
        editor.execute([
          DeleteNodeRequest(nodeId: node.id),
        ]);
      },
    );
  }

  @override
  Widget? createComponent(SingleColumnDocumentComponentContext context,
      SingleColumnLayoutComponentViewModel viewModel) {
    if (viewModel is! _AttachmentViewModel) return null;
    return switch (viewModel.node) {
      ImageAttachmentNode n => _ImageAttachmentWidget(
          componentKey: context.componentKey,
          node: n,
          selection: viewModel.selection?.nodeSelection as UpstreamDownstreamNodeSelection?,
          selectionColor: viewModel.selectionColor,
          onDelete: viewModel.onDelete,
          collapseImages: viewModel.collapseImages,
        ),
      FileAttachmentNode n => _FileAttachmentWidget(
          componentKey: context.componentKey,
          node: n,
          selection: viewModel.selection?.nodeSelection as UpstreamDownstreamNodeSelection?,
          selectionColor: viewModel.selectionColor,
          onDelete: viewModel.onDelete,
        ),
      RichLinkNode n => _RichLinkAttachmentWidget(
          componentKey: context.componentKey,
          node: n,
          selection: viewModel.selection?.nodeSelection as UpstreamDownstreamNodeSelection?,
          selectionColor: viewModel.selectionColor,
        ),
      _ => null,
    };
  }
}

class _AttachmentViewModel extends SingleColumnLayoutComponentViewModel with SelectionAwareViewModelMixin {
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
  _AttachmentViewModel copy() =>
      _AttachmentViewModel(
        nodeId: nodeId,
        node: node,
        onDelete: onDelete,
        collapseImages: collapseImages,
        selection: selection,
        selectionColor: selectionColor,
      );

  @override
  bool operator ==(Object other) =>
      other is _AttachmentViewModel && other.node.url == node.url;

  @override
  int get hashCode => node.url.hashCode;
}

class _ImageAttachmentWidget extends StatelessWidget {
  const _ImageAttachmentWidget({
    required this.componentKey,
    required this.node,
    required this.onDelete,
    required this.collapseImages,
    this.selection,
    required this.selectionColor,
  });

  final GlobalKey componentKey;
  final ImageAttachmentNode node;
  final VoidCallback onDelete;
  final bool collapseImages;
  final UpstreamDownstreamNodeSelection? selection;
  final Color selectionColor;

  @override
  Widget build(BuildContext context) {
    final isUploading = node.metadata['isUploading'] == true;
    final cs = Theme.of(context).colorScheme;

    late final Widget child;
    if (isUploading) {
      child = Container(
        height: 160,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Enviando foto...',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: onDelete,
                color: cs.outline,
                tooltip: 'Cancelar envio',
              ),
            ),
          ],
        ),
      );
    } else if (collapseImages) {
      child = InkWell(
        onTap: () => launchUrl(Uri.parse(node.url)),
        borderRadius: BorderRadius.circular(32),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.surfaceContainer.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(Icons.image_outlined, color: cs.onSurfaceVariant, size: 22),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      node.fileName,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Imagem',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.outline, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      child = Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              node.url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
            ),
          ),
        ],
      );
    }

    return SelectableBox(
      selection: selection,
      selectionColor: selectionColor,
      child: BoxComponent(
        key: componentKey,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: child,
        ),
      ),
    );
  }
}

class _FileAttachmentWidget extends StatelessWidget {
  const _FileAttachmentWidget({
    required this.componentKey,
    required this.node,
    required this.onDelete,
    this.selection,
    required this.selectionColor,
  });

  final GlobalKey componentKey;
  final FileAttachmentNode node;
  final VoidCallback onDelete;
  final UpstreamDownstreamNodeSelection? selection;
  final Color selectionColor;

  String _formatBytes(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final isUploading = node.metadata['isUploading'] == true;
    final cs = Theme.of(context).colorScheme;

    return SelectableBox(
      selection: selection,
      selectionColor: selectionColor,
      child: BoxComponent(
        key: componentKey,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: InkWell(
            onTap: isUploading ? null : () => launchUrl(Uri.parse(node.url)),
            borderRadius: BorderRadius.circular(32),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainer.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: isUploading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.primary,
                              ),
                            )
                          : Icon(
                              node.isVideo
                                  ? Icons.play_circle_outline
                                  : Icons.insert_drive_file,
                              color: cs.onSurfaceVariant,
                              size: 22,
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          node.fileName,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isUploading ? 'Enviando...' : _formatBytes(node.fileSize),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: cs.outline,
                                fontSize: 12,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (isUploading) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: onDelete,
                      color: cs.outline,
                      tooltip: 'Cancelar envio',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RichLinkAttachmentWidget extends StatelessWidget {
  const _RichLinkAttachmentWidget({
    required this.componentKey,
    required this.node,
    this.selection,
    required this.selectionColor,
  });

  final GlobalKey componentKey;
  final RichLinkNode node;
  final UpstreamDownstreamNodeSelection? selection;
  final Color selectionColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasPreview = node.title != null || node.description != null;

    return SelectableBox(
      selection: selection,
      selectionColor: selectionColor,
      child: BoxComponent(
        key: componentKey,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: InkWell(
            onTap: () => launchUrl(Uri.parse(node.url)),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (node.imageUrl != null)
                  Image.network(node.imageUrl!,
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox()),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(node.domain ?? node.url,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: cs.outline)),
                        if (hasPreview) ...[
                          if (node.title != null)
                            Text(node.title!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall),
                          if (node.description != null)
                            Text(node.description!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant)),
                        ],
                      ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

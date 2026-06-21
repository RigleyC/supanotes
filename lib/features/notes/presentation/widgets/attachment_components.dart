import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/attachment_nodes.dart';

class AttachmentComponentBuilder implements ComponentBuilder {
  const AttachmentComponentBuilder({
    required this.editor,
  });

  final Editor editor;

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
      Document document, DocumentNode node) {
    if (node is! AttachmentNode) return null;
    return _AttachmentViewModel(
      nodeId: node.id,
      node: node,
      createdAt: node.metadata[NodeMetadata.createdAt],
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
          key: context.componentKey,
          node: n,
          onDelete: viewModel.onDelete,
        ),
      FileAttachmentNode n => _FileAttachmentWidget(
          key: context.componentKey,
          node: n,
          onDelete: viewModel.onDelete,
        ),
      RichLinkNode n => _RichLinkAttachmentWidget(
          key: context.componentKey,
          node: n,
        ),
      _ => null,
    };
  }
}

class _AttachmentViewModel extends SingleColumnLayoutComponentViewModel {
  _AttachmentViewModel({
    required super.nodeId,
    required this.node,
    required this.onDelete,
    super.createdAt,
    super.padding = EdgeInsets.zero,
  });

  final AttachmentNode node;
  final VoidCallback onDelete;

  @override
  _AttachmentViewModel copy() =>
      _AttachmentViewModel(nodeId: nodeId, node: node, onDelete: onDelete);

  @override
  bool operator ==(Object other) =>
      other is _AttachmentViewModel && other.node.url == node.url;

  @override
  int get hashCode => node.url.hashCode;
}

class _ImageAttachmentWidget extends StatelessWidget {
  const _ImageAttachmentWidget({super.key, required this.node, required this.onDelete});
  final ImageAttachmentNode node;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isUploading = node.metadata['isUploading'] == true;
    final isFailed = node.metadata['isFailed'] == true;
    final cs = Theme.of(context).colorScheme;

    if (isUploading || isFailed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(
          height: 160,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Stack(
            children: [
              Center(
                child: isUploading
                    ? Column(
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
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, color: cs.error, size: 28),
                          const SizedBox(height: 8),
                          Text(
                            'Falha ao enviar foto',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.error),
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
                  color: isFailed ? cs.error : cs.outline,
                  tooltip: 'Remover foto',
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          node.url,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
        ),
      ),
    );
  }
}

class _FileAttachmentWidget extends StatelessWidget {
  const _FileAttachmentWidget({super.key, required this.node, required this.onDelete});
  final FileAttachmentNode node;
  final VoidCallback onDelete;

  String _formatBytes(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final isUploading = node.metadata['isUploading'] == true;
    final isFailed = node.metadata['isFailed'] == true;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: (isUploading || isFailed) ? null : () => launchUrl(Uri.parse(node.url)),
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
                          isFailed
                              ? Icons.error_outline
                              : (node.isVideo
                                  ? Icons.play_circle_outline
                                  : Icons.insert_drive_file),
                          color: isFailed ? cs.error : cs.onSurfaceVariant,
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
                      isUploading
                          ? 'Enviando...'
                          : (isFailed ? 'Falha no envio' : _formatBytes(node.fileSize)),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isFailed ? cs.error : cs.outline,
                            fontSize: 12,
                          ),
                    ),
                  ],
                ),
              ),
              if (isFailed || isUploading) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onDelete,
                  color: isFailed ? cs.error : cs.outline,
                  tooltip: 'Remover anexo',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RichLinkAttachmentWidget extends StatelessWidget {
  const _RichLinkAttachmentWidget({super.key, required this.node});
  final RichLinkNode node;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasPreview = node.title != null || node.description != null;

    return Padding(
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
    );
  }
}

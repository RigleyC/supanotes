import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/attachment_nodes.dart';

class AttachmentComponentBuilder implements ComponentBuilder {
  const AttachmentComponentBuilder();

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
      Document document, DocumentNode node) {
    if (node is! AttachmentNode) return null;
    return _AttachmentViewModel(
      nodeId: node.id,
      node: node,
      createdAt: node.metadata[NodeMetadata.createdAt],
    );
  }

  @override
  Widget? createComponent(SingleColumnDocumentComponentContext context,
      SingleColumnLayoutComponentViewModel viewModel) {
    if (viewModel is! _AttachmentViewModel) return null;
    return switch (viewModel.node) {
      ImageAttachmentNode n => _ImageAttachmentWidget(node: n),
      FileAttachmentNode n => _FileAttachmentWidget(node: n),
      RichLinkNode n => _RichLinkAttachmentWidget(node: n),
      _ => null,
    };
  }
}

class _AttachmentViewModel extends SingleColumnLayoutComponentViewModel {
  _AttachmentViewModel({
    required super.nodeId,
    required this.node,
    super.createdAt,
    super.padding = EdgeInsets.zero,
  });

  final AttachmentNode node;

  @override
  _AttachmentViewModel copy() =>
      _AttachmentViewModel(nodeId: nodeId, node: node);

  @override
  bool operator ==(Object other) =>
      other is _AttachmentViewModel && other.node.url == node.url;

  @override
  int get hashCode => node.url.hashCode;
}

class _ImageAttachmentWidget extends StatelessWidget {
  const _ImageAttachmentWidget({required this.node});
  final ImageAttachmentNode node;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            node.url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
          ),
        ),
      );
}

class _FileAttachmentWidget extends StatelessWidget {
  const _FileAttachmentWidget({required this.node});
  final FileAttachmentNode node;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: () => launchUrl(Uri.parse(node.url)),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Row(children: [
            Icon(
              node.isVideo
                  ? Icons.play_circle_outline
                  : Icons.insert_drive_file,
              color: cs.primary,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(node.fileName,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          ]),
        ),
      ),
    );
  }
}

class _RichLinkAttachmentWidget extends StatelessWidget {
  const _RichLinkAttachmentWidget({required this.node});
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

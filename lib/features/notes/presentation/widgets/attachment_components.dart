import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:url_launcher/url_launcher.dart';

import 'attachment_nodes.dart';

class ImageAttachmentComponentBuilder implements ComponentBuilder {
  const ImageAttachmentComponentBuilder();

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
      Document document, DocumentNode node) {
    if (node is! ImageAttachmentNode) return null;
    return _ImageAttachmentViewModel(
      nodeId: node.id,
      node: node,
      createdAt: node.metadata[NodeMetadata.createdAt],
    );
  }

  @override
  Widget? createComponent(SingleColumnDocumentComponentContext context,
      SingleColumnLayoutComponentViewModel viewModel) {
    if (viewModel is! _ImageAttachmentViewModel) return null;
    return _ImageAttachmentComponent(viewModel: viewModel);
  }
}

class _ImageAttachmentViewModel extends SingleColumnLayoutComponentViewModel {
  _ImageAttachmentViewModel({
    required super.nodeId,
    required this.node,
    super.createdAt,
    super.padding = EdgeInsets.zero,
  });

  final ImageAttachmentNode node;

  @override
  _ImageAttachmentViewModel copy() =>
      _ImageAttachmentViewModel(nodeId: nodeId, node: node);

  @override
  bool operator ==(Object other) =>
      other is _ImageAttachmentViewModel && other.node.url == node.url;

  @override
  int get hashCode => node.url.hashCode;
}

class _ImageAttachmentComponent extends StatelessWidget {
  const _ImageAttachmentComponent({required this.viewModel});
  final _ImageAttachmentViewModel viewModel;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            viewModel.node.url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
          ),
        ),
      );
}

class FileAttachmentComponentBuilder implements ComponentBuilder {
  const FileAttachmentComponentBuilder();

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
      Document document, DocumentNode node) {
    if (node is! FileAttachmentNode) return null;
    return _FileAttachmentViewModel(
      nodeId: node.id,
      node: node,
      createdAt: node.metadata[NodeMetadata.createdAt],
    );
  }

  @override
  Widget? createComponent(SingleColumnDocumentComponentContext context,
      SingleColumnLayoutComponentViewModel viewModel) {
    if (viewModel is! _FileAttachmentViewModel) return null;
    return _FileAttachmentComponent(viewModel: viewModel);
  }
}

class _FileAttachmentViewModel extends SingleColumnLayoutComponentViewModel {
  _FileAttachmentViewModel({
    required super.nodeId,
    required this.node,
    super.createdAt,
    super.padding = EdgeInsets.zero,
  });

  final FileAttachmentNode node;

  @override
  _FileAttachmentViewModel copy() =>
      _FileAttachmentViewModel(nodeId: nodeId, node: node);

  @override
  bool operator ==(Object other) =>
      other is _FileAttachmentViewModel && other.node.url == node.url;

  @override
  int get hashCode => node.url.hashCode;
}

class _FileAttachmentComponent extends StatelessWidget {
  const _FileAttachmentComponent({required this.viewModel});
  final _FileAttachmentViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final node = viewModel.node;
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
              node.isVideo ? Icons.play_circle_outline : Icons.insert_drive_file,
              color: cs.primary, size: 32,
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

class RichLinkComponentBuilder implements ComponentBuilder {
  const RichLinkComponentBuilder();

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
      Document document, DocumentNode node) {
    if (node is! RichLinkNode) return null;
    return _RichLinkViewModel(
      nodeId: node.id,
      node: node,
      createdAt: node.metadata[NodeMetadata.createdAt],
    );
  }

  @override
  Widget? createComponent(SingleColumnDocumentComponentContext context,
      SingleColumnLayoutComponentViewModel viewModel) {
    if (viewModel is! _RichLinkViewModel) return null;
    return _RichLinkComponent(viewModel: viewModel);
  }
}

class _RichLinkViewModel extends SingleColumnLayoutComponentViewModel {
  _RichLinkViewModel({
    required super.nodeId,
    required this.node,
    super.createdAt,
    super.padding = EdgeInsets.zero,
  });

  final RichLinkNode node;

  @override
  _RichLinkViewModel copy() =>
      _RichLinkViewModel(nodeId: nodeId, node: node);

  @override
  bool operator ==(Object other) =>
      other is _RichLinkViewModel && other.node.url == node.url;

  @override
  int get hashCode => node.url.hashCode;
}

class _RichLinkComponent extends StatelessWidget {
  const _RichLinkComponent({required this.viewModel});
  final _RichLinkViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final node = viewModel.node;
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
                  height: 160, width: double.infinity, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox()),
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

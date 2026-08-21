import 'dart:io';

import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:supanotes/features/notes/editor/document/attachment_nodes.dart';

class AttachmentUploadingCapsule extends StatelessWidget {
  const AttachmentUploadingCapsule({
    super.key,
    required this.fileName,
    this.onCancel,
  });

  final String fileName;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
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
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.primary,
                ),
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
                  fileName,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  'Enviando...',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.outline,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (onCancel != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: onCancel,
              color: cs.outline,
              tooltip: 'Cancelar envio',
            ),
          ],
        ],
      ),
    );
  }
}

class AttachmentFailedCapsule extends StatelessWidget {
  const AttachmentFailedCapsule({
    super.key,
    required this.fileName,
    this.onDelete,
  });

  final String fileName;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: cs.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.errorContainer.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(Icons.error_outline, color: cs.error, size: 22),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fileName,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  'Falha ao enviar',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.error,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (onDelete != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: onDelete,
              color: cs.error,
              tooltip: 'Remover',
            ),
          ],
        ],
      ),
    );
  }
}

class AttachmentFilePill extends StatelessWidget {
  const AttachmentFilePill({
    super.key,
    required this.fileName,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String fileName;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
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
                child: Icon(icon, color: cs.onSurfaceVariant, size: 22),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fileName,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.outline,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AttachmentExpandedImage extends StatelessWidget {
  const AttachmentExpandedImage({super.key, required this.url, this.localPath});

  final String url;
  final String? localPath;

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;
    final file = localPath != null ? File(localPath!) : null;
    if (file != null && file.existsSync()) {
      imageWidget = Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildNetworkImage(context),
      );
    } else {
      imageWidget = _buildNetworkImage(context);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: imageWidget,
    );
  }

  Widget _buildNetworkImage(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          height: 180,
          color: cs.surfaceContainerHighest,
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.primary,
              ),
            ),
          ),
        );
      },
      errorBuilder: (_, _, _) => Container(
        height: 120,
        color: cs.surfaceContainerHighest,
        child: Center(
          child: Icon(Icons.broken_image, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

class AttachmentRichLinkCard extends StatelessWidget {
  const AttachmentRichLinkCard({
    super.key,
    required this.componentKey,
    required this.node,
    this.selection,
    required this.selectionColor,
    this.allowInternalNoteLinks = true,
  });

  final GlobalKey componentKey;
  final RichLinkNode node;
  final UpstreamDownstreamNodeSelection? selection;
  final Color selectionColor;
  final bool allowInternalNoteLinks;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final linkUrl = node.url ?? '';
    final parsedLink = Uri.tryParse(linkUrl);
    final canOpenLink =
        parsedLink != null &&
        (parsedLink.scheme == 'http' ||
            parsedLink.scheme == 'https' ||
            (allowInternalNoteLinks && parsedLink.scheme == 'note'));

    return SelectableBox(
      selection: selection,
      selectionColor: selectionColor,
      child: BoxComponent(
        key: componentKey,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: InkWell(
            onTap: canOpenLink ? () => launchUrl(parsedLink) : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (node.imageUrl != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          node.imageUrl!,
                          height: 88,
                          width: 88,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            height: 88,
                            width: 88,
                            color: cs.surfaceContainer,
                            child: Icon(Icons.link, color: cs.onSurfaceVariant),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (node.title != null) ...[
                            Text(
                              node.title!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            if (node.description != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  node.description!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                node.siteName ?? node.domain ?? linkUrl,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: cs.outline),
                              ),
                            ),
                          ] else ...[
                            Text(
                              node.domain ?? linkUrl,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            if (node.domain != null && linkUrl.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  linkUrl,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

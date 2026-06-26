import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/attachment_nodes.dart';

class AttachmentUploadingCapsule extends StatelessWidget {
  const AttachmentUploadingCapsule({super.key, 
    required this.fileName,
    required this.onCancel,
  });

  final String fileName;
  final VoidCallback onCancel;

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
                    strokeWidth: 2, color: cs.primary),
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
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  'Enviando...',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.outline, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: onCancel,
            color: cs.outline,
            tooltip: 'Cancelar envio',
          ),
        ],
      ),
    );
  }
}

class AttachmentFailedCapsule extends StatelessWidget {
  const AttachmentFailedCapsule({super.key, 
    required this.fileName,
    required this.onDelete,
  });

  final String fileName;
  final VoidCallback onDelete;

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
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  'Falha ao enviar',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.error, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: onDelete,
            color: cs.error,
            tooltip: 'Remover',
          ),
        ],
      ),
    );
  }
}

class AttachmentFilePill extends StatelessWidget {
  const AttachmentFilePill({super.key, 
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
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.outline, fontSize: 12),
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
  const AttachmentExpandedImage({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
      ),
    );
  }
}

class AttachmentRichLinkCard extends StatelessWidget {
  const AttachmentRichLinkCard({super.key, 
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
    final linkUrl = node.url ?? '';

    return SelectableBox(
      selection: selection,
      selectionColor: selectionColor,
      child: BoxComponent(
        key: componentKey,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: InkWell(
            onTap: linkUrl.isNotEmpty
                ? () => launchUrl(Uri.parse(linkUrl))
                : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                            Text(node.domain ?? linkUrl,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: cs.outline)),
                            if (hasPreview) ...[
                              if (node.title != null)
                                Text(node.title!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall),
                              if (node.description != null)
                                Text(node.description!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                            color: cs.onSurfaceVariant)),
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

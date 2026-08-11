import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_editor/super_editor.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:supanotes/core/utils/format_utils.dart';
import 'package:supanotes/features/notes/attachments/domain/attachment_delivery.dart';
import 'package:supanotes/features/notes/attachments/data/attachments_repository.dart';
import 'package:supanotes/features/notes/attachments/model/attachment_model.dart';
import 'attachment_renderers.dart';

class DocumentAttachmentWidget extends ConsumerWidget {
  const DocumentAttachmentWidget({
    super.key,
    required this.componentKey,
    required this.nodeId,
    required this.attachmentId,
    this.onDelete,
    required this.collapseImages,
    this.fallbackUrl,
    this.fallbackFileName,
    this.deliveryPreference = AttachmentDeliveryPreference.localFirst,
    this.attachmentDelivery,
    this.selection,
    required this.selectionColor,
  });

  final GlobalKey componentKey;
  final String nodeId;
  final String attachmentId;
  final VoidCallback? onDelete;
  final bool collapseImages;
  final String? fallbackUrl;
  final String? fallbackFileName;
  final AttachmentDeliveryPreference deliveryPreference;
  final AttachmentDelivery? attachmentDelivery;
  final UpstreamDownstreamNodeSelection? selection;
  final Color selectionColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachmentAsync = ref.watch(attachmentByIdProvider(attachmentId));

    Widget fallbackAttachment() {
      final url = fallbackUrl;
      if (url == null || url.isEmpty) {
        return AttachmentUploadingCapsule(
          fileName: fallbackFileName ?? '...',
          onCancel: onDelete,
        );
      }
      return AttachmentFilePill(
        fileName: fallbackFileName ?? 'Anexo',
        subtitle: 'Anexo compartilhado',
        icon: Icons.attach_file,
        onTap: () => _openAttachment(url, fileName: fallbackFileName),
      );
    }

    final Widget child = attachmentAsync.when(
      data: (model) {
        if (deliveryPreference == AttachmentDeliveryPreference.externalFirst &&
            fallbackUrl != null) {
          return fallbackAttachment();
        }
        if (model == null) {
          return fallbackAttachment();
        }

        switch (model.status) {
          case AttachmentStatus.uploading:
            return AttachmentUploadingCapsule(
              fileName: model.fileName,
              onCancel: onDelete,
            );
          case AttachmentStatus.failed:
            return AttachmentFailedCapsule(
              fileName: model.fileName,
              onDelete: onDelete,
            );
          case AttachmentStatus.local:
          case AttachmentStatus.synced:
            final url = model.displayUrl;
            if (url == null) return const SizedBox.shrink();

            if (model.type == AttachmentType.image) {
              if (collapseImages) {
                return AttachmentFilePill(
                  fileName: model.fileName,
                  subtitle: 'Imagem',
                  icon: Icons.image_outlined,
                  onTap: () => _openAttachment(
                    url,
                    useDelivery: model.remoteUrl != null,
                    fileName: model.fileName,
                  ),
                );
              }
              return AttachmentExpandedImage(
                url: url,
                localPath: model.localPath,
              );
            }

            return AttachmentFilePill(
              fileName: model.fileName,
              subtitle: formatBytes(model.fileSize),
              icon: model.type == AttachmentType.video
                  ? Icons.play_circle_outline
                  : Icons.insert_drive_file,
              onTap: url.isNotEmpty
                  ? () => _openAttachment(
                      url,
                      useDelivery: model.remoteUrl != null,
                      fileName: model.fileName,
                    )
                  : () {},
            );
        }
      },
      loading: fallbackAttachment,
      error: (_, _) => fallbackAttachment(),
    );

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

  void _openAttachment(
    String url, {
    bool useDelivery = true,
    String? fileName,
  }) {
    final delivery = useDelivery ? attachmentDelivery : null;
    if (delivery == null) {
      launchUrl(Uri.parse(url));
      return;
    }
    unawaited(
      delivery
          .open(attachmentId, Uri.parse(url), fileName: fileName)
          .catchError((Object error, StackTrace stackTrace) {
            dev.log(
              'Failed to open attachment $attachmentId',
              error: error,
              stackTrace: stackTrace,
            );
          }),
    );
  }
}

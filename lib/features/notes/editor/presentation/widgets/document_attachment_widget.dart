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
    this.fallbackAttachment,
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
  final AttachmentReference? fallbackAttachment;
  final AttachmentDeliveryPreference deliveryPreference;
  final AttachmentDelivery? attachmentDelivery;
  final UpstreamDownstreamNodeSelection? selection;
  final Color selectionColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachmentAsync = ref.watch(attachmentByIdProvider(attachmentId));

    Widget buildFallbackAttachment() {
      final attachment = fallbackAttachment;
      if (attachment == null || attachment.id.isEmpty) {
        return AttachmentUploadingCapsule(
          fileName: attachment?.fileName ?? '...',
          onCancel: onDelete,
        );
      }
      return AttachmentFilePill(
        fileName: attachment.fileName,
        subtitle: 'Anexo compartilhado',
        icon: Icons.attach_file,
        onTap: () => _openAttachment(null, attachment: attachment),
      );
    }

    final Widget child = attachmentAsync.when(
      data: (model) {
        if (deliveryPreference == AttachmentDeliveryPreference.externalFirst &&
            fallbackAttachment != null) {
          return buildFallbackAttachment();
        }
        if (model == null) {
          return buildFallbackAttachment();
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
                    attachment: model.remoteUrl == null
                        ? null
                        : AttachmentReference(
                            id: attachmentId,
                            fileName: model.fileName,
                          ),
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
                      attachment: model.remoteUrl == null
                          ? null
                          : AttachmentReference(
                              id: attachmentId,
                              fileName: model.fileName,
                            ),
                    )
                  : () {},
            );
        }
      },
      loading: buildFallbackAttachment,
      error: (_, _) => buildFallbackAttachment(),
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

  void _openAttachment(String? url, {AttachmentReference? attachment}) {
    final delivery = attachmentDelivery;
    if (delivery == null) {
      if (url != null) launchUrl(Uri.parse(url));
      return;
    }
    if (attachment == null) return;
    unawaited(
      delivery.open(attachment).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        dev.log(
          'Failed to open attachment $attachmentId',
          error: error,
          stackTrace: stackTrace,
        );
      }),
    );
  }
}

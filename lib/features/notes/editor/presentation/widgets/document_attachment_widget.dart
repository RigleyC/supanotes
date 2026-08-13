import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_editor/super_editor.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:supanotes/core/utils/format_utils.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:supanotes/features/notes/attachments/domain/attachment_delivery.dart';
import 'package:supanotes/features/notes/attachments/data/attachments_repository.dart';
import 'package:supanotes/features/notes/attachments/model/attachment_model.dart';
import 'attachment_renderers.dart';

typedef _OpenAttachmentCallback =
    Future<void> Function(String? url, {AttachmentReference? attachment});

class DocumentAttachmentWidget extends StatelessWidget {
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
  Widget build(BuildContext context) => SelectableBox(
    selection: selection,
    selectionColor: selectionColor,
    child: BoxComponent(
      key: componentKey,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _DocumentAttachmentContent(
          attachmentId: attachmentId,
          onDelete: onDelete,
          collapseImages: collapseImages,
          fallbackAttachment: fallbackAttachment,
          deliveryPreference: deliveryPreference,
          attachmentDelivery: attachmentDelivery,
        ),
      ),
    ),
  );
}

class _DocumentAttachmentContent extends ConsumerWidget {
  const _DocumentAttachmentContent({
    required this.attachmentId,
    required this.collapseImages,
    required this.deliveryPreference,
    required this.attachmentDelivery,
    this.onDelete,
    this.fallbackAttachment,
  });

  final String attachmentId;
  final VoidCallback? onDelete;
  final bool collapseImages;
  final AttachmentReference? fallbackAttachment;
  final AttachmentDeliveryPreference deliveryPreference;
  final AttachmentDelivery? attachmentDelivery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = _AttachmentFallback(
      fallbackAttachment: fallbackAttachment,
      onDelete: onDelete,
      onOpen: _openAttachment,
    );
    final attachmentAsync = ref.watch(attachmentByIdProvider(attachmentId));

    return attachmentAsync.when(
      data: (model) => _AttachmentData(
        model: model,
        fallback: fallback,
        fallbackAttachment: fallbackAttachment,
        deliveryPreference: deliveryPreference,
        collapseImages: collapseImages,
        attachmentId: attachmentId,
        onDelete: onDelete,
        attachmentDelivery: attachmentDelivery,
        onOpen: _openAttachment,
      ),
      loading: () => fallback,
      error: (_, _) => fallback,
    );
  }

  Future<void> _openAttachment(
    String? url, {
    AttachmentReference? attachment,
  }) async {
    try {
      final delivery = attachmentDelivery;
      if (delivery == null) {
        if (url == null || !await launchUrl(Uri.parse(url))) {
          throw StateError('Could not open attachment');
        }
        return;
      }
      if (attachment == null) return;
      await delivery.open(attachment);
    } catch (error, stackTrace) {
      dev.log(
        'Failed to open attachment $attachmentId',
        error: error,
        stackTrace: stackTrace,
      );
      AppMessenger.showError('Falha ao abrir anexo');
    }
  }
}

class _AttachmentFallback extends StatelessWidget {
  const _AttachmentFallback({
    required this.fallbackAttachment,
    required this.onOpen,
    this.onDelete,
  });

  final AttachmentReference? fallbackAttachment;
  final VoidCallback? onDelete;
  final _OpenAttachmentCallback onOpen;

  @override
  Widget build(BuildContext context) {
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
      onTap: () => unawaited(onOpen(null, attachment: attachment)),
    );
  }
}

class _AttachmentData extends StatelessWidget {
  const _AttachmentData({
    required this.model,
    required this.fallback,
    required this.fallbackAttachment,
    required this.deliveryPreference,
    required this.collapseImages,
    required this.attachmentId,
    required this.attachmentDelivery,
    required this.onOpen,
    this.onDelete,
  });

  final AttachmentModel? model;
  final Widget fallback;
  final AttachmentReference? fallbackAttachment;
  final AttachmentDeliveryPreference deliveryPreference;
  final bool collapseImages;
  final String attachmentId;
  final VoidCallback? onDelete;
  final AttachmentDelivery? attachmentDelivery;
  final _OpenAttachmentCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final attachment = model;
    if (attachment == null ||
        (deliveryPreference == AttachmentDeliveryPreference.externalFirst &&
            fallbackAttachment != null)) {
      return fallback;
    }

    switch (attachment.status) {
      case AttachmentStatus.uploading:
        return AttachmentUploadingCapsule(
          fileName: attachment.fileName,
          onCancel: onDelete,
        );
      case AttachmentStatus.failed:
        return AttachmentFailedCapsule(
          fileName: attachment.fileName,
          onDelete: onDelete,
        );
      case AttachmentStatus.local:
      case AttachmentStatus.synced:
        return _AttachmentReady(
          model: attachment,
          attachmentId: attachmentId,
          collapseImages: collapseImages,
          attachmentDelivery: attachmentDelivery,
          onOpen: onOpen,
        );
    }
  }
}

class _AttachmentReady extends StatelessWidget {
  const _AttachmentReady({
    required this.model,
    required this.attachmentId,
    required this.collapseImages,
    required this.attachmentDelivery,
    required this.onOpen,
  });

  final AttachmentModel model;
  final String attachmentId;
  final bool collapseImages;
  final AttachmentDelivery? attachmentDelivery;
  final _OpenAttachmentCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final url = model.displayUrl;
    if (url == null) return const SizedBox.shrink();

    final isImage = model.type == AttachmentType.image;
    final showImagePill =
        isImage &&
        (collapseImages ||
            (attachmentDelivery != null && model.localPath == null));
    if (showImagePill) {
      final attachment = collapseImages
          ? _remoteAttachment
          : _deliveryAttachment;
      return AttachmentFilePill(
        fileName: model.fileName,
        subtitle: 'Imagem',
        icon: Icons.image_outlined,
        onTap: () => unawaited(onOpen(url, attachment: attachment)),
      );
    }
    if (isImage) {
      return AttachmentExpandedImage(url: url, localPath: model.localPath);
    }

    return AttachmentFilePill(
      fileName: model.fileName,
      subtitle: formatBytes(model.fileSize),
      icon: model.type == AttachmentType.video
          ? Icons.play_circle_outline
          : Icons.insert_drive_file,
      onTap: url.isNotEmpty
          ? () => unawaited(onOpen(url, attachment: _remoteAttachment))
          : () {},
    );
  }

  AttachmentReference? get _remoteAttachment => model.remoteUrl == null
      ? null
      : AttachmentReference(id: attachmentId, fileName: model.fileName);

  AttachmentReference get _deliveryAttachment =>
      AttachmentReference(id: attachmentId, fileName: model.fileName);
}

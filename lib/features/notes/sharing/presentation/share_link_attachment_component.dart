import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:supanotes/core/constants/api_constants.dart';
import 'package:supanotes/features/notes/editor/document/attachment_nodes.dart';
import 'package:supanotes/shared/widgets/app_selection_tile.dart';

class ShareLinkAttachmentComponentBuilder implements ComponentBuilder {
  const ShareLinkAttachmentComponentBuilder({required this.token});

  final String token;

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is! AttachmentNode) return null;
    return _ShareLinkAttachmentViewModel(
      nodeId: node.id,
      node: node,
      token: token,
      createdAt: node.metadata[NodeMetadata.createdAt],
    );
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext context,
    SingleColumnLayoutComponentViewModel viewModel,
  ) {
    if (viewModel is! _ShareLinkAttachmentViewModel) return null;
    return _ShareLinkAttachmentComponent(
      componentKey: context.componentKey,
      node: viewModel.node,
      token: viewModel.token,
      selection:
          viewModel.selection?.nodeSelection
              as UpstreamDownstreamNodeSelection?,
      selectionColor: viewModel.selectionColor,
    );
  }
}

class _ShareLinkAttachmentViewModel extends SingleColumnLayoutComponentViewModel
    with SelectionAwareViewModelMixin {
  _ShareLinkAttachmentViewModel({
    required super.nodeId,
    required this.node,
    required this.token,
    super.createdAt,
    super.padding = EdgeInsets.zero,
    DocumentNodeSelection? selection,
    Color selectionColor = Colors.transparent,
  }) {
    super.selection = selection;
    super.selectionColor = selectionColor;
  }

  final AttachmentNode node;
  final String token;

  @override
  _ShareLinkAttachmentViewModel copy() => _ShareLinkAttachmentViewModel(
    nodeId: nodeId,
    node: node,
    token: token,
    createdAt: createdAt,
    padding: padding,
    selection: selection,
    selectionColor: selectionColor,
  );

  @override
  bool operator ==(Object other) =>
      other is _ShareLinkAttachmentViewModel &&
      other.node.id == node.id &&
      other.token == token;

  @override
  int get hashCode => Object.hash(node.id, token);
}

class _ShareLinkAttachmentComponent extends StatelessWidget {
  const _ShareLinkAttachmentComponent({
    required this.componentKey,
    required this.node,
    required this.token,
    required this.selection,
    required this.selectionColor,
  });

  final GlobalKey componentKey;
  final AttachmentNode node;
  final String token;
  final UpstreamDownstreamNodeSelection? selection;
  final Color selectionColor;

  @override
  Widget build(BuildContext context) {
    return SelectableBox(
      selection: selection,
      selectionColor: selectionColor,
      child: BoxComponent(
        key: componentKey,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: switch (node) {
            DocumentAttachmentNode n => _AttachmentCard(node: n, token: token),
            RichLinkNode n => _RichLinkCard(node: n),
            _ => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }
}

class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({required this.node, required this.token});

  final DocumentAttachmentNode node;
  final String token;

  @override
  Widget build(BuildContext context) {
    final attachmentID = node.metadata['attachmentId'] ?? node.id;
    final filename = node.metadata['filename'];
    if (attachmentID is! String || attachmentID.isEmpty) {
      return const Text('Anexo indisponível');
    }
    final url = publicShareLinkAttachmentUrl(token, attachmentID);
    return AppSelectionTile(
      label: filename is String && filename.isNotEmpty ? filename : 'Anexo',
      icon: Icons.attach_file,
      onTap: () => unawaited(launchUrl(url)),
    );
  }
}

class _RichLinkCard extends StatelessWidget {
  const _RichLinkCard({required this.node});

  final RichLinkNode node;

  @override
  Widget build(BuildContext context) {
    final url = _safeWebUri(node.url);
    final imageUrl = _safeWebUri(node.imageUrl);
    final title = node.title?.trim();
    final description = node.description?.trim();
    final displayTitle = title == null || title.isEmpty
        ? url?.toString()
        : title;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (imageUrl != null)
          Image.network(
            imageUrl.toString(),
            width: double.infinity,
            height: 160,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        AppSelectionTile(
          label: displayTitle ?? node.domain ?? url?.host ?? 'Link',
          icon: Icons.link,
          onTap: url == null ? null : () => unawaited(launchUrl(url)),
        ),
        if (description != null && description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

Uri? _safeWebUri(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return uri;
}

Uri publicShareLinkAttachmentUrl(String token, String attachmentID) {
  final base = Uri.parse(ApiConstants.baseUrl);
  const apiPath = '/api/v1';
  final rootPath = base.path.endsWith(apiPath)
      ? base.path.substring(0, base.path.length - apiPath.length)
      : base.path;
  return base.replace(
    path:
        '${rootPath.isEmpty ? '' : rootPath}/s/${Uri.encodeComponent(token)}/attachments/${Uri.encodeComponent(attachmentID)}',
    query: null,
    fragment: null,
  );
}

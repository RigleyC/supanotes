import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:supanotes/core/constants/api_constants.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/notes/sharing/model/share_link_document.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';

final _shareLinkDocumentProvider = FutureProvider.autoDispose
    .family<ShareLinkDocument, String>((ref, token) async {
      final response = await ref
          .read(apiClientProvider)
          .get<Map<String, dynamic>>('/s/$token/document');
      return ShareLinkDocument.fromJson(response.data ?? const {});
    });

class ShareLinkReaderScreen extends ConsumerWidget {
  const ShareLinkReaderScreen({required this.token, super.key});

  final String token;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref.watch(_shareLinkDocumentProvider(token));
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.medium(title: Text('Nota compartilhada')),
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: document.when(
              data: (value) => SliverList.list(
                children: [
                  Text(
                    value.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 24),
                  ...value.blocks.asMap().entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ShareLinkBlockView(
                        block: entry.value,
                        index: entry.key,
                        token: token,
                      ),
                    ),
                  ),
                ],
              ),
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => const SliverFillRemaining(
                child: AppErrorView(title: 'Não foi possível abrir esta nota.'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareLinkBlockView extends StatelessWidget {
  const _ShareLinkBlockView({
    required this.block,
    required this.index,
    required this.token,
  });

  final ShareLinkBlock block;
  final int index;
  final String token;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyLarge;
    return switch (block.type) {
      'header1' => _ShareLinkRichText(
        block: block,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      'header2' => _ShareLinkRichText(
        block: block,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      'header3' => _ShareLinkRichText(
        block: block,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      'quote' => DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 3,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: _ShareLinkRichText(block: block, style: textStyle),
        ),
      ),
      'bulletList' => _ShareLinkListItem(
        marker: '•',
        block: block,
        style: textStyle,
      ),
      'orderedList' => _ShareLinkListItem(
        marker: '${index + 1}.',
        block: block,
        style: textStyle,
      ),
      'task' => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IgnorePointer(
            child: Checkbox(
              value:
                  block.metadata['isCompleted'] == true ||
                  block.metadata['checked'] == true,
              onChanged: (_) {},
            ),
          ),
          Expanded(
            child: _ShareLinkRichText(block: block, style: textStyle),
          ),
        ],
      ),
      'divider' => const Divider(),
      'attachment' => _ShareLinkAttachment(block: block, token: token),
      'rich_link' => _ShareLinkRichLink(block: block),
      _ => _ShareLinkRichText(block: block, style: textStyle),
    };
  }
}

class _ShareLinkListItem extends StatelessWidget {
  const _ShareLinkListItem({
    required this.marker,
    required this.block,
    required this.style,
  });

  final String marker;
  final ShareLinkBlock block;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 28, child: Text(marker, style: style)),
        Expanded(
          child: _ShareLinkRichText(block: block, style: style),
        ),
      ],
    );
  }
}

class _ShareLinkRichText extends StatefulWidget {
  const _ShareLinkRichText({required this.block, required this.style});

  final ShareLinkBlock block;
  final TextStyle? style;

  @override
  State<_ShareLinkRichText> createState() => _ShareLinkRichTextState();
}

class _ShareLinkRichTextState extends State<_ShareLinkRichText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    final spans = <TextSpan>[];
    for (final operation in widget.block.delta) {
      final insert = operation['insert'];
      if (insert is! String || insert.isEmpty) continue;
      final attributes = operation['attributes'] is Map
          ? Map<String, dynamic>.from(operation['attributes'] as Map)
          : const <String, dynamic>{};
      final rawLink = attributes['link'];
      final link = rawLink is String ? Uri.tryParse(rawLink) : null;
      final safeLink =
          link != null && (link.scheme == 'http' || link.scheme == 'https')
          ? link
          : null;
      TapGestureRecognizer? recognizer;
      if (safeLink != null) {
        recognizer = TapGestureRecognizer()
          ..onTap = () => unawaited(launchUrl(safeLink));
        _recognizers.add(recognizer);
      }
      spans.add(
        TextSpan(
          text: insert,
          recognizer: recognizer,
          style: TextStyle(
            fontWeight: attributes['bold'] == true ? FontWeight.bold : null,
            fontStyle: attributes['italic'] == true ? FontStyle.italic : null,
            decoration: safeLink != null ? TextDecoration.underline : null,
            color: safeLink != null
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
        ),
      );
    }
    return SelectableText.rich(TextSpan(style: widget.style, children: spans));
  }
}

class _ShareLinkAttachment extends StatelessWidget {
  const _ShareLinkAttachment({required this.block, required this.token});

  final ShareLinkBlock block;
  final String token;

  @override
  Widget build(BuildContext context) {
    final attachmentID = block.metadata['attachmentId'] as String? ?? block.id;
    final filename = block.metadata['filename'] as String? ?? 'Anexo';
    final url = _publicAttachmentUrl(token, attachmentID);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.attach_file),
        title: Text(filename),
        subtitle: const Text('Abrir anexo'),
        onTap: () => unawaited(launchUrl(url)),
      ),
    );
  }
}

class _ShareLinkRichLink extends StatelessWidget {
  const _ShareLinkRichLink({required this.block});

  final ShareLinkBlock block;

  @override
  Widget build(BuildContext context) {
    final rawUrl = block.metadata['url'];
    final url = rawUrl is String ? Uri.tryParse(rawUrl) : null;
    final safeUrl =
        url != null && (url.scheme == 'http' || url.scheme == 'https')
        ? url
        : null;
    final title = block.metadata['title'] as String? ?? block.text;
    final description = block.metadata['description'] as String?;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.link),
        title: Text(title.isEmpty ? 'Link' : title),
        subtitle: description == null ? null : Text(description),
        onTap: safeUrl == null ? null : () => unawaited(launchUrl(safeUrl)),
      ),
    );
  }
}

Uri _publicAttachmentUrl(String token, String attachmentID) {
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

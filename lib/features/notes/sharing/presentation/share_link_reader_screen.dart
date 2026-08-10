import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                  ...value.blocks.map(
                    (block) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SelectableText(block.text),
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

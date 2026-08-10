import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/notes/sharing/model/share_link_document.dart';

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
      appBar: AppBar(title: const Text('Nota compartilhada')),
      body: document.when(
        data: (value) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(value.title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            ...value.blocks.map(
              (block) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SelectableText(block.text),
              ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Não foi possível abrir esta nota.')),
      ),
    );
  }
}

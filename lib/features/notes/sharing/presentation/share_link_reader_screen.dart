import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/di/providers.dart';

final _shareLinkDocumentProvider = FutureProvider.autoDispose
    .family<({String title, String text}), String>((ref, token) async {
      final response = await ref
          .read(apiClientProvider)
          .get<Map<String, dynamic>>('/s/$token/document');
      return (
        title:
            response.data?['title'] as String? ??
            'Nota compartilhada no SupaNotes',
        text: response.data?['text'] as String? ?? '',
      );
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
            SelectableText(value.text),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Não foi possível abrir esta nota.')),
      ),
    );
  }
}

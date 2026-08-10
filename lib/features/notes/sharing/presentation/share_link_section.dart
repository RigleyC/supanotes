import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/features/notes/sharing/data/share_link_repository.dart';
import 'package:supanotes/shared/widgets/app_button.dart';

class ShareLinkSection extends ConsumerStatefulWidget {
  const ShareLinkSection({required this.noteId, super.key});

  final String noteId;

  @override
  ConsumerState<ShareLinkSection> createState() => _ShareLinkSectionState();
}

class _ShareLinkSectionState extends ConsumerState<ShareLinkSection> {
  AsyncValue<void> _action = const AsyncData(null);

  Future<void> _activate({bool replace = false}) async {
    setState(() => _action = const AsyncLoading());
    try {
      await ref
          .read(shareLinkRepositoryProvider)
          .activate(widget.noteId, replace: replace);
      ref.invalidate(shareLinkStatusProvider(widget.noteId));
      if (mounted) setState(() => _action = const AsyncData(null));
    } catch (error, stackTrace) {
      if (mounted) setState(() => _action = AsyncError(error, stackTrace));
    }
  }

  Future<void> _disable() async {
    setState(() => _action = const AsyncLoading());
    try {
      await ref.read(shareLinkRepositoryProvider).disable(widget.noteId);
      ref.invalidate(shareLinkStatusProvider(widget.noteId));
      if (mounted) setState(() => _action = const AsyncData(null));
    } catch (error, stackTrace) {
      if (mounted) setState(() => _action = AsyncError(error, stackTrace));
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(shareLinkStatusProvider(widget.noteId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Link público', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        status.when(
          loading: () => const CircularProgressIndicator(),
          error: (error, _) => Text('Não foi possível consultar o link.'),
          data: (link) => link.active && link.url != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(link.url!),
                    Wrap(
                      spacing: 8,
                      children: [
                        AppButton(
                          text: 'Copiar',
                          onPressed: () =>
                              Clipboard.setData(ClipboardData(text: link.url!)),
                        ),
                        AppButton(
                          text: 'Substituir',
                          onPressed: _action.isLoading
                              ? null
                              : () => _activate(replace: true),
                        ),
                        AppButton(
                          text: 'Revogar',
                          onPressed: _action.isLoading ? null : _disable,
                        ),
                      ],
                    ),
                  ],
                )
              : AppButton(
                  text: 'Ativar link público',
                  isLoading: _action.isLoading,
                  onPressed: _action.isLoading ? null : _activate,
                ),
        ),
        if (_action.hasError)
          Text(
            'Não foi possível alterar o link.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}

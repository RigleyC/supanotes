import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/notes/sharing/application/share_link_access_provider.dart';
import 'package:supanotes/features/notes/sharing/presentation/share_link_reader_screen.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';

class ShareLinkAccessScreen extends ConsumerStatefulWidget {
  const ShareLinkAccessScreen({required this.token, super.key});

  final String token;

  @override
  ConsumerState<ShareLinkAccessScreen> createState() =>
      _ShareLinkAccessScreenState();
}

class _ShareLinkAccessScreenState extends ConsumerState<ShareLinkAccessScreen> {
  bool _redirectScheduled = false;

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(shareLinkAccessProvider(widget.token));
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.medium(title: Text('Nota compartilhada')),
          SliverFillRemaining(
            child: access.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const AppErrorView(
                title: 'Este link é inválido ou foi revogado.',
                subtitle: 'Peça ao proprietário uma nova permissão.',
              ),
              data: (decision) {
                if (decision.canEdit) {
                  _scheduleEditorRedirect(context, decision.noteId);
                  return const Center(child: CircularProgressIndicator());
                }
                return ShareLinkReaderScreen(token: widget.token);
              },
            ),
          ),
        ],
      ),
    );
  }

  void _scheduleEditorRedirect(BuildContext context, String noteId) {
    if (_redirectScheduled) return;
    _redirectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(AppRoutes.note(noteId));
    });
  }
}

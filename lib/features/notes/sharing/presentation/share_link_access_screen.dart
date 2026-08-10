import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_open_options.dart';
import 'package:supanotes/features/notes/sharing/application/share_link_access_provider.dart';
import 'package:supanotes/features/notes/sharing/application/share_link_access_resolver.dart';
import 'package:supanotes/features/notes/sharing/domain/share_link_strings.dart';
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
          const SliverAppBar.medium(
            title: Text(ShareLinkStrings.sharedNoteTitle),
          ),
          SliverFillRemaining(
            child: access.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const AppErrorView(
                title: ShareLinkStrings.accessErrorTitle,
                subtitle: ShareLinkStrings.accessErrorSubtitle,
              ),
              data: (decision) {
                if (decision.mode != ShareLinkAccessMode.guest) {
                  _scheduleEditorRedirect(
                    context,
                    decision.noteId,
                    accessMode: decision.mode == ShareLinkAccessMode.viewer
                        ? NoteEditorAccessMode.readOnly
                        : NoteEditorAccessMode.editable,
                  );
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

  void _scheduleEditorRedirect(
    BuildContext context,
    String noteId, {
    required NoteEditorAccessMode accessMode,
  }) {
    if (_redirectScheduled) return;
    _redirectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(
        AppRoutes.note(noteId),
        extra: NoteEditorOpenOptions(
          accessMode: accessMode,
          shareLinkToken: widget.token,
        ),
      );
    });
  }
}

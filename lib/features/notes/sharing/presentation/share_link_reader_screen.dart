import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/notes/editor/presentation/note_desktop_stylesheet.dart';
import 'package:supanotes/features/notes/editor/presentation/note_mobile_stylesheet.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/custom_divider_component.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/custom_task_component.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/attachment_components.dart';
import 'package:supanotes/features/notes/sharing/data/share_link_attachment_url.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_link_tap_handler.dart';
import 'package:supanotes/features/notes/sharing/domain/share_link_strings.dart';
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
    return document.when(
      data: (value) => Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverAppBar.medium(title: Text(value.title)),
            SliverFillRemaining(
              hasScrollBody: true,
              child: _ShareLinkDocumentReader(document: value, token: token),
            ),
          ],
        ),
      ),
      loading: () => const Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverAppBar.medium(title: Text(ShareLinkStrings.sharedNoteTitle)),
            SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      ),
      error: (_, _) => const Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverAppBar.medium(title: Text(ShareLinkStrings.sharedNoteTitle)),
            SliverFillRemaining(
              child: AppErrorView(title: ShareLinkStrings.readerErrorTitle),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareLinkDocumentReader extends StatefulWidget {
  const _ShareLinkDocumentReader({required this.document, required this.token});

  final ShareLinkDocument document;
  final String token;

  @override
  State<_ShareLinkDocumentReader> createState() =>
      _ShareLinkDocumentReaderState();
}

class _ShareLinkDocumentReaderState extends State<_ShareLinkDocumentReader> {
  late final Editor _editor;

  @override
  void initState() {
    super.initState();
    _editor = createDefaultDocumentEditor(
      document: widget.document.snapshot.toMutableDocument(),
    );
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 700;
    final documentPadding = const EdgeInsets.fromLTRB(24, 24, 24, 48);
    final stylesheet = isDesktop
        ? desktopNoteStylesheet(context, documentPadding: documentPadding)
        : mobileNoteStylesheet(context, documentPadding: documentPadding);
    return SuperReader(
      editor: _editor,
      stylesheet: stylesheet,
      componentBuilders: [
        const CustomDividerComponentBuilder(),
        CustomTaskComponentBuilder(
          editor: _editor,
          composer: _editor.composer,
          readOnly: true,
        ),
        AttachmentComponentBuilder(
          editor: _editor,
          collapseImages: false,
          readOnly: true,
          allowInternalNoteLinks: false,
          attachmentDelivery: ShareLinkAttachmentDelivery(widget.token),
        ),
        ...defaultComponentBuilders,
      ],
      contentTapDelegateFactory: (readerContext) => NoteLinkTapHandler(
        readerContext.document,
        webOnly: true,
        allowInternalNoteLinks: false,
        onNoteTap: (targetId) => context.push(AppRoutes.note(targetId)),
      ),
      key: ValueKey<bool>(isDesktop),
    );
  }
}

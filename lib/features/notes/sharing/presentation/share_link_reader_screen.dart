import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_codec.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_editor.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_style.dart';
import 'package:supanotes/features/notes/editor/document/note_blocks.dart';
import 'package:supanotes/features/notes/sharing/data/share_link_attachment_url.dart';
import 'package:supanotes/features/notes/sharing/domain/share_link_strings.dart';
import 'package:supanotes/features/notes/sharing/model/share_link_document.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';

final shareLinkDocumentProvider = FutureProvider.autoDispose
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
    final document = ref.watch(shareLinkDocumentProvider(token));
    return document.when(
      data: (value) => Scaffold(
        // The editor scrolls the note itself, under the collapsing title.
        body: NestedScrollView(
          headerSliverBuilder: (_, _) => [
            SliverAppBar.medium(title: Text(value.title)),
          ],
          body: _ShareLinkDocumentReader(document: value, token: token),
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
  late final EditorState _editorState = EditorState(
    document: const NoteAppFlowyCodec().toDocument(
      noteBlocksFromSnapshot(widget.document.snapshot.toJson()),
    ),
  )..editable = false;

  @override
  void dispose() {
    _editorState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NoteAppFlowyEditor(
      key: const ValueKey('share-link-reader'),
      editorState: _editorState,
      readOnly: true,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
      attachmentDelivery: ShareLinkAttachmentDelivery(widget.token),
      // Only web links open; links to the owner's other notes do not.
      links: const NoteLinkHandler(
        allowInternalNoteLinks: false,
        webOnly: true,
      ),
    );
  }
}

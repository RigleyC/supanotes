import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/notes/attachments/domain/attachment_delivery.dart';
import 'package:supanotes/features/notes/attachments/domain/attachment_upload.dart';
import 'package:supanotes/features/notes/editor/appflowy/blocks/note_task_block.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_editor.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_style.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_controller.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_delegate.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_session.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_format_commands.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_link_picker_sheet.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_selection_menu.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_suggestion_overlay.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_toolbar.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

/// The note body: the document editor plus, while editing, its toolbar.
class NoteEditor extends StatefulWidget {
  const NoteEditor({
    required this.noteId,
    required this.session,
    required this.delegate,
    required this.attachmentUploader,
    super.key,
    this.hideCompleted = false,
    this.collapseImages = false,
    this.attachmentDelivery,
    this.requestInitialFocus = false,
    this.isReadOnly = false,
    this.header,
  });

  final String noteId;
  final NoteEditorSession session;
  final bool hideCompleted;
  final bool collapseImages;
  final AttachmentDelivery? attachmentDelivery;
  final bool requestInitialFocus;
  final NoteEditorDelegate delegate;
  final AttachmentUploader attachmentUploader;

  /// Write access is owned by the screen, which already watches the session
  /// capability stream. The editor only renders the resulting mode.
  final bool isReadOnly;

  /// Shown above the first block, scrolling with the note.
  final Widget? header;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late EditorScrollController _scrollController;

  /// Height the floating toolbar covers at the bottom of the editor,
  /// including its margins.
  static const _toolbarClearance = 72.0;

  NoteEditorController get _controller => widget.session.controller;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      _scrollController.dispose();
      _attach();
    }
    _controller.hideCompleted = widget.hideCompleted;
  }

  void _attach() {
    _controller.hideCompleted = widget.hideCompleted;
    _scrollController = EditorScrollController(
      editorState: _controller.editorState,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _hideKeyboard() {
    _controller.editorState.selection = null;
    _controller.focusNode.unfocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
  }

  Future<void> _linkNote() async {
    final editorState = _controller.editorState;
    final selection = editorState.selection;
    if (selection == null || selection.isCollapsed) return;
    final note = await pickNoteToLink(context, currentNoteId: widget.noteId);
    if (note == null || !mounted) return;
    _controller.editAt(selection);
    await editorState.linkSelectionToNote(note.id);
  }

  Future<void> _attachFile({bool imageOnly = false}) async {
    try {
      await _controller.pickAndAttachFile(
        uploader: widget.attachmentUploader,
        imageOnly: imageOnly,
      );
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'supanotes note editor',
          context: ErrorDescription('while attaching a file to a note'),
        ),
      );
      if (mounted) {
        AppMessenger.showError('Não foi possível anexar o arquivo');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final editorState = _controller.editorState;
    final delegate = widget.delegate;
    final editor = NoteAppFlowyEditor(
      key: ValueKey<bool>(widget.isReadOnly),
      editorState: editorState,
      readOnly: widget.isReadOnly,
      hideCompleted: widget.hideCompleted,
      collapseImages: widget.collapseImages,
      attachmentDelivery: widget.attachmentDelivery,
      scrollController: _scrollController,
      header: widget.header,
      focusNode: _controller.focusNode,
      autoFocus: widget.requestInitialFocus && !widget.isReadOnly,
      // AppFlowy applies this padding to every block, so it stays
      // horizontal; the room under the last line is the footer.
      padding: const EdgeInsets.symmetric(
        horizontal: NoteEditorMetrics.horizontalPadding,
      ),
      footer: SizedBox(height: widget.isReadOnly ? 24 : _toolbarClearance + 24),
      // AppFlowy keeps half of this box visible below the caret, which must
      // clear the toolbar floating over the note.
      autoScrollEdgeOffset: (_toolbarClearance + 32) * 2,
      links: NoteLinkHandler(
        allowInternalNoteLinks: !widget.isReadOnly,
        onNoteTap: (targetId) => context.push(AppRoutes.note(targetId)),
      ),
      taskActions: widget.isReadOnly
          ? const NoteTaskActions()
          : NoteTaskActions(
              onComplete: (id) async => delegate.onTaskComplete?.call(id),
              onReopen: (id, scheduledAt) async =>
                  delegate.onTaskReopen?.call(id, scheduledAt),
              onOpenDetails: (id) => delegate.onTaskLongPress?.call(id),
              onHidden: (_) => unawaited(_controller.refreshHidden()),
            ),
    );
    if (widget.isReadOnly) return editor;

    return TapRegion(
      groupId: noteEditorToolbarTapRegionGroup,
      // The note scrolls behind the floating toolbar instead of ending above
      // it.
      child: Stack(
        children: [
          Positioned.fill(
            child: NoteSelectionMenu(
              editorState: editorState,
              editing: _controller.editing,
              scrollController: _scrollController,
              child: editor,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                NoteSuggestionOverlay(
                  editorState: editorState,
                  currentNoteId: widget.noteId,
                ),
                // Rebuilds only when editing starts or stops, not on every
                // caret move: the toolbar listens to the selection itself.
                // Shown only while editing.
                ValueListenableBuilder<bool>(
                  valueListenable: _controller.editing,
                  builder: (context, editing, _) => !editing
                      ? const SizedBox.shrink()
                      : NoteToolbar(
                          editorState: editorState,
                          onAttachFile: () => _attachFile(),
                          onAttachImage: () => _attachFile(imageOnly: true),
                          onHideKeyboard: _hideKeyboard,
                          onLinkNote: () => unawaited(_linkNote()),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

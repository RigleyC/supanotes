import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
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

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late EditorScrollController _scrollController;

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

  /// Tapping below the last block continues writing at the end of the note,
  /// adding an empty line when the note ends with a divider or attachment.
  void _focusEnd() {
    if (widget.isReadOnly) return;
    final editorState = _controller.editorState;
    final last = editorState.document.root.children.lastOrNull;
    if (last == null || last.delta == null) {
      final path = [editorState.document.root.children.length];
      unawaited(
        editorState.apply(
          editorState.transaction
            ..insertNode(path, paragraphNode())
            ..afterSelection = Selection.collapsed(Position(path: path)),
        ),
      );
      return;
    }
    var node = last;
    while (node.children.isNotEmpty) {
      node = node.children.last;
    }
    editorState.selection = Selection.collapsed(
      Position(path: node.path, offset: node.delta?.length ?? 0),
    );
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
      focusNode: _controller.focusNode,
      autoFocus: widget.requestInitialFocus && !widget.isReadOnly,
      padding: const EdgeInsets.symmetric(
        horizontal: NoteEditorMetrics.horizontalPadding,
      ),
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
            ),
      footer: GestureDetector(
        key: const ValueKey('note-editor-end'),
        behavior: HitTestBehavior.opaque,
        // AppFlowy clears the selection after a pointer goes down on its
        // header or footer (in a post-frame callback); place the caret in a
        // later one so it wins.
        onTap: () {
          WidgetsBinding.instance
            ..addPostFrameCallback((_) {
              if (mounted) _focusEnd();
            })
            ..scheduleFrame();
        },
        child: const SizedBox(height: 160, width: double.infinity),
      ),
    );
    if (widget.isReadOnly) return editor;

    return TapRegion(
      groupId: noteEditorToolbarTapRegionGroup,
      child: Column(
        children: [
          Expanded(child: editor),
          // Rebuilds only when editing starts or stops, not on every caret
          // move: the toolbar listens to the selection itself.
          ValueListenableBuilder<Selection?>(
            valueListenable: editorState.selectionNotifier,
            builder: (context, selection, toolbar) =>
                selection == null ? const SizedBox.shrink() : toolbar!,
            child: NoteToolbar(
              editorState: editorState,
              onAttachFile: () => _attachFile(),
              onAttachImage: () => _attachFile(imageOnly: true),
            ),
          ),
        ],
      ),
    );
  }
}

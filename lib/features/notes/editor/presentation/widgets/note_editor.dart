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
import 'package:supanotes/features/notes/editor/presentation/widgets/note_format_panel.dart';
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

class _NoteEditorState extends State<NoteEditor> with WidgetsBindingObserver {
  late EditorScrollController _scrollController;

  /// The "Formatar" panel is showing in the keyboard's place.
  bool _panelOpen = false;

  /// Last height of the on-screen keyboard; the panel takes the same space so
  /// the note does not move when they swap.
  double _keyboardHeight = 291;

  /// The keyboard inset at the previous metrics change, to tell a rising
  /// keyboard from one that is going away.
  double _lastInset = 0;

  /// Space the floating toolbar covers at the bottom of the editor.
  static const _toolbarClearance = 88.0;

  NoteEditorController get _controller => widget.session.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attach();
  }

  @override
  void didChangeMetrics() {
    final view = View.of(context);
    final inset = view.viewInsets.bottom / view.devicePixelRatio;
    final rising = inset > _lastInset;
    _lastInset = inset;
    // Opening the panel hides the keyboard, and every frame of that animation
    // reports a smaller inset. Only a keyboard coming up counts: it means the
    // user tapped the text, so the keyboard replaces the panel.
    if (rising && inset >= 100) {
      _keyboardHeight = inset;
      if (_panelOpen) setState(() => _panelOpen = false);
    } else if (_panelOpen) {
      // The panel grows into the space the keyboard frees.
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.controller.editing.removeListener(_onSelection);
      _scrollController.dispose();
      _panelOpen = false;
      _attach();
    }
    _controller.hideCompleted = widget.hideCompleted;
  }

  void _attach() {
    _controller.editing.addListener(_onSelection);
    _controller.hideCompleted = widget.hideCompleted;
    _scrollController = EditorScrollController(
      editorState: _controller.editorState,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.editing.removeListener(_onSelection);
    _scrollController.dispose();
    super.dispose();
  }

  /// Editing ended: the panel goes away with the toolbar.
  void _onSelection() {
    if (_panelOpen && !_controller.editing.value) {
      setState(() => _panelOpen = false);
    }
  }

  void _togglePanel() {
    final open = !_panelOpen;
    setState(() => _panelOpen = open);
    unawaited(
      SystemChannels.textInput.invokeMethod<void>(
        open ? 'TextInput.hide' : 'TextInput.show',
      ),
    );
  }

  void _hideKeyboard() {
    setState(() => _panelOpen = false);
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
      // Room at the end so the last line can scroll clear of the toolbar,
      // and the caret is kept above it while typing.
      padding: EdgeInsets.fromLTRB(
        NoteEditorMetrics.horizontalPadding,
        0,
        NoteEditorMetrics.horizontalPadding,
        widget.isReadOnly ? 24 : _toolbarClearance,
      ),
      autoScrollEdgeOffset: _toolbarClearance + 16,
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
      child: Column(
        children: [
          Expanded(
            // The note scrolls behind the floating toolbar instead of ending
            // above it.
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
                      // Rebuilds only when editing starts or stops, not on
                      // every caret move: the toolbar listens to the
                      // selection itself. Shown only while editing, and
                      // replaced by the format panel while that is open (the
                      // panel has its own close button).
                      ValueListenableBuilder<bool>(
                        valueListenable: _controller.editing,
                        builder: (context, editing, _) => !editing || _panelOpen
                            ? const SizedBox.shrink()
                            : NoteToolbar(
                                editorState: editorState,
                                panelOpen: _panelOpen,
                                onTogglePanel: _togglePanel,
                                onAttachFile: () => _attachFile(),
                                onAttachImage: () =>
                                    _attachFile(imageOnly: true),
                                onHideKeyboard: _hideKeyboard,
                                onLinkNote: () => unawaited(_linkNote()),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_panelOpen)
            NoteFormatPanel(
              editorState: editorState,
              // Until the keyboard is gone the screen is still shortened by
              // it, so the panel only fills what it has freed.
              height: (_keyboardHeight - _lastInset).clamp(
                0,
                _keyboardHeight,
              ),
              onClose: _togglePanel,
            ),
        ],
      ),
    );
  }
}

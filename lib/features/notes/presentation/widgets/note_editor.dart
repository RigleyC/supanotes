library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mime/mime.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/notes/data/markdown_serializer.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_delegate.dart';
import 'package:supanotes/features/notes/presentation/note_stylesheet.dart';
import 'package:supanotes/features/notes/presentation/widgets/attachment_components.dart';
import 'package:supanotes/features/notes/presentation/widgets/custom_divider_component.dart';
import 'package:supanotes/features/notes/presentation/widgets/custom_task_component.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_suggestion_overlay.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_link_tap_handler.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_toolbar.dart';
import 'package:supanotes/features/notes/presentation/widgets/rich_common_editor_operations.dart';
import 'package:supanotes/features/notes/presentation/widgets/rich_ios_controls_controller.dart';
import 'package:supanotes/features/notes/presentation/widgets/rich_keyboard_actions.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';

class NoteEditor extends ConsumerStatefulWidget {
  final String noteId;
  final String content;
  final Map<String, TaskModel> taskMetadata;
  final bool hideCompleted;
  final bool collapseImages;
  final bool isReadOnly;
  final NoteEditorDelegate delegate;

  const NoteEditor({
    super.key,
    required this.noteId,
    required this.content,
    required this.taskMetadata,
    this.hideCompleted = false,
    this.collapseImages = false,
    this.isReadOnly = false,
    required this.delegate,
  });

  @override
  ConsumerState<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends ConsumerState<NoteEditor> {
  NoteEditorController? _controller;
  final _docLayoutKey = GlobalKey();
  RichSuperEditorIosControlsController? _iosController;
  SuperEditorAndroidControlsController? _androidController;
  RichCommonEditorOperations? _richOps;
  String _lastContent = '';
  bool _hasLocalEdits = false;

  late CustomTaskComponentBuilder _taskComponentBuilder;

  @override
  void initState() {
    super.initState();
    _lastContent = widget.content;
    _controller = NoteEditorController(
      snapshotSave: widget.isReadOnly
          ? (noteId, markdown, tasks) async {}
          : widget.delegate.snapshotSave,
      emptyNoteExit: widget.isReadOnly ? null : widget.delegate.emptyNoteExit,
    );
    _controller!.bind(widget.noteId);
    _controller!.init(content: widget.content);
    if (!widget.isReadOnly) {
      _controller!.document?.addListener(_onDocumentChanged);
      if (widget.content.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _controller?.focusNode?.requestFocus();
        });
      }
    }
    _notifyContentChanged();

    _taskComponentBuilder = CustomTaskComponentBuilder(
      _controller!.editor!,
      taskMetadataById: widget.taskMetadata,
      hideCompleted: widget.hideCompleted,
      onTaskLongPress: widget.isReadOnly
          ? null
          : (taskId) => widget.delegate.onTaskLongPress?.call(
              widget.taskMetadata[taskId],
              () => _controller!.persistSnapshotNow(),
            ),
      onTaskComplete: widget.delegate.onTaskComplete,
      onTaskReopen: widget.delegate.onTaskReopen,
      requestRebuild: () {
        if (mounted) setState(() {});
      },
    );
  }

  void _setupControls(BuildContext context) {
    if (_richOps != null) return;
    final controller = _controller!;
    if (controller.editor == null || controller.composer == null) return;

    final editorControlsColor = Theme.of(context).colorScheme.primary;

    _richOps = RichCommonEditorOperations(
      editor: controller.editor!,
      document: controller.editor!.document,
      composer: controller.composer!,
      documentLayoutResolver: () => _docLayoutKey.currentState as DocumentLayout,
    );

    _iosController = RichSuperEditorIosControlsController(
      editor: controller.editor!,
      documentLayoutResolver: () => _docLayoutKey.currentState as DocumentLayout,
      operations: _richOps!,
      handleColor: editorControlsColor,
    );

    _androidController = SuperEditorAndroidControlsController(
      controlsColor: editorControlsColor,
      toolbarBuilder: (overlayContext, mobileToolbarKey, focalPoint) =>
          defaultAndroidEditorToolbarBuilder(
            overlayContext,
            mobileToolbarKey,
            _richOps!,
            SuperEditorAndroidControlsScope.rootOf(overlayContext),
            controller.composer!.selectionNotifier,
            focalPoint,
          ),
    );
  }

  @override
  void didUpdateWidget(NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _taskComponentBuilder.taskMetadataById = widget.taskMetadata;
    _taskComponentBuilder.hideCompleted = widget.hideCompleted;
    _taskComponentBuilder.onTaskLongPress = widget.isReadOnly
        ? null
        : (taskId) => widget.delegate.onTaskLongPress?.call(
            widget.taskMetadata[taskId],
            () => _controller?.persistSnapshotNow() ?? Future.value(),
          );
    final doc = _controller?.document;
    if (doc != null) {
      final currentMarkdown = serializeNoteToMarkdown(doc);
      if (widget.content == currentMarkdown) {
        _hasLocalEdits = false;
        _lastContent = widget.content;
      }
    }

    if (widget.content != oldWidget.content && !_hasLocalEdits && widget.content != _lastContent) {
      _lastContent = widget.content;
      _controller?.init(content: widget.content);
    }
  }

  @override
  void dispose() {
    if (!widget.isReadOnly) {
      _controller?.document?.removeListener(_onDocumentChanged);
    }
    _iosController?.dispose();
    _androidController?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _onDocumentChanged(DocumentChangeLog _) {
    _hasLocalEdits = true;
    _notifyContentChanged();
  }

  void _notifyContentChanged() {
    final doc = _controller?.document;
    widget.delegate.onHasContentChanged?.call(doc != null && doc.isNotEmpty);
  }

  Future<void> _onAttach({bool imageOnly = false}) async {
    final uploader = widget.delegate.onUploadFile;
    if (uploader == null || _controller?.editor == null) return;

    final result = await FilePicker.platform.pickFiles(
      type: imageOnly ? FileType.image : FileType.any,
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.single;
    final path = picked.path;
    if (path == null) return;

    final mimeType = lookupMimeType(path) ?? 'application/octet-stream';

    _controller!.attachFileFromPath(
      filePath: path,
      mimeType: mimeType,
      onUploadFile: uploader,
      onError: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Falha ao enviar anexo')),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;

    if (controller.document == null ||
        controller.editor == null ||
        controller.composer == null) {
      return const Center(child: CircularProgressIndicator());
    }

    _setupControls(context);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SuperEditorAndroidControlsScope(
                  controller: _androidController!,
                  child: SuperEditorIosControlsScope(
                    controller: _iosController!,
                    child: SuperEditor(
                      editor: controller.editor!,
                      focusNode: widget.isReadOnly
                          ? null
                          : controller.focusNode,
                      documentLayoutKey: _docLayoutKey,
                      stylesheet: noteStylesheet(
                        context,
                        hideCompleted: widget.hideCompleted,
                      ),
                      selectionStyle: SelectionStyles(
                        selectionColor:
                            Theme.of(
                              context,
                            ).textSelectionTheme.selectionColor ??
                            Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.4),
                      ),
                      contentTapDelegateFactories: widget.isReadOnly
                          ? null
                          : [
                              (editContext) => NoteLinkTapHandler(
                                    editContext.document,
                                    editContext.composer,
                                    onNoteTap: (targetId) =>
                                        context.push(AppRoutes.note(targetId)),
                                  ),
                              superEditorLaunchLinkTapHandlerFactory,
                            ],
                      keyboardActions: buildRichKeyboardActions(
                        baseActions:
                            defaultTargetPlatform == TargetPlatform.iOS ||
                                defaultTargetPlatform == TargetPlatform.android
                            ? defaultImeKeyboardActions
                            : defaultKeyboardActions,
                      ),
                      componentBuilders: [
                        const CustomDividerComponentBuilder(),
                        _taskComponentBuilder,
                        AttachmentComponentBuilder(
                          editor: controller.editor!,
                          collapseImages: widget.collapseImages,
                        ),
                        ...defaultComponentBuilders,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!widget.isReadOnly)
            NoteSuggestionOverlay(
              editor: controller.editor!,
              composer: controller.composer!,
              currentNoteId: widget.noteId,
              onPersist: () => controller.persistSnapshotNow(),
            ),
          if (!widget.isReadOnly)
            NoteToolbar(
              editor: controller.editor!,
              composer: controller.composer!,
              onAttachFile: () => _onAttach(imageOnly: false),
              onAttachImage: () => _onAttach(imageOnly: true),
            ),
        ],
      ),
    );
  }

}

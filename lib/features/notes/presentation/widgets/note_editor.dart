library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/domain/attachment_model.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';
import 'package:supanotes/features/notes/presentation/note_stylesheet.dart';
import 'package:supanotes/features/notes/presentation/widgets/attachment_components.dart';
import 'package:supanotes/features/notes/presentation/widgets/attachment_nodes.dart';
import 'package:supanotes/features/notes/presentation/widgets/custom_divider_component.dart';
import 'package:supanotes/features/notes/presentation/widgets/custom_task_component.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_toolbar.dart';
import 'package:supanotes/features/notes/presentation/widgets/rich_common_editor_operations.dart';
import 'package:supanotes/features/notes/presentation/widgets/rich_ios_controls_controller.dart';
import 'package:supanotes/features/notes/presentation/widgets/rich_keyboard_actions.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';

class NoteEditor extends StatefulWidget {
  final String noteId;
  final String content;
  final Map<String, TaskModel> taskMetadata;
  final bool hideCompleted;
  final bool isReadOnly;
  final SnapshotSave snapshotSave;
  final EmptyNoteExit? emptyNoteExit;
  final ValueChanged<bool>? onHasContentChanged;
  final void Function(String taskId, Future<void> Function() flushSnapshot)?
  onTaskLongPress;
  final Future<void> Function(String taskId)? onTaskComplete;
  final Future<void> Function(String taskId)? onTaskReopen;
  final Future<AttachmentModel> Function(String noteId, File file, String mimeType)?
  onUploadFile;

  const NoteEditor({
    super.key,
    required this.noteId,
    required this.content,
    required this.taskMetadata,
    this.hideCompleted = false,
    this.isReadOnly = false,
    required this.snapshotSave,
    this.emptyNoteExit,
    this.onHasContentChanged,
    this.onTaskLongPress,
    this.onTaskComplete,
    this.onTaskReopen,
    this.onUploadFile,
  });

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  NoteEditorController? _controller;
  final _docLayoutKey = GlobalKey();
  RichSuperEditorIosControlsController? _iosController;
  SuperEditorAndroidControlsController? _androidController;
  RichCommonEditorOperations? _richOps;

  late CustomTaskComponentBuilder _taskComponentBuilder;

  @override
  void initState() {
    super.initState();
    _controller = NoteEditorController(
      snapshotSave: widget.isReadOnly
          ? (noteId, markdown, tasks) async {}
          : widget.snapshotSave,
      emptyNoteExit: widget.isReadOnly ? null : widget.emptyNoteExit,
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
          : (taskId) => widget.onTaskLongPress?.call(
              taskId,
              () => _controller!.persistSnapshotNow(),
            ),
      onTaskComplete: widget.onTaskComplete,
      onTaskReopen: widget.onTaskReopen,
      requestRebuild: () {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void didUpdateWidget(NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _taskComponentBuilder.taskMetadataById = widget.taskMetadata;
    _taskComponentBuilder.hideCompleted = widget.hideCompleted;
    _taskComponentBuilder.onTaskLongPress = widget.isReadOnly
        ? null
        : (taskId) => widget.onTaskLongPress?.call(
            taskId,
            () => _controller?.persistSnapshotNow() ?? Future.value(),
          );
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

  void _onDocumentChanged(DocumentChangeLog _) => _notifyContentChanged();

  void _notifyContentChanged() {
    final doc = _controller?.document;
    widget.onHasContentChanged?.call(doc != null && doc.isNotEmpty);
  }

  Future<void> _onAttach() async {
    if (widget.onUploadFile == null) return;
    if (_controller?.editor == null) return;

    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final path = picked.path;
    if (path == null) return;
    final file = File(path);
    final ext = picked.extension?.toLowerCase() ?? '';
    final mimeType = _mimeFromExtension(ext);

    late final AttachmentModel attachment;
    try {
      attachment = await widget.onUploadFile!(widget.noteId, file, mimeType);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Falha ao enviar anexo')),
        );
      }
      return;
    }

    final url = attachment.displayUrl ?? '';
    final DocumentNode node = attachment.type == AttachmentType.image
        ? ImageAttachmentNode(
            id: attachment.id, url: url, fileName: attachment.fileName,
          )
        : FileAttachmentNode(
            id: attachment.id, url: url,
            fileName: attachment.fileName, mimeType: attachment.mimeType,
          );

    _controller!.editor!.execute([
      InsertNodeAtCaretRequest(node: node),
    ]);
  }

  String _mimeFromExtension(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
      case 'docx':
        return 'application/msword';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;

    if (controller.document == null ||
        controller.editor == null ||
        controller.composer == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final editorControlsColor = Theme.of(context).colorScheme.primary;

    _richOps ??= RichCommonEditorOperations(
      editor: controller.editor!,
      document: controller.editor!.document,
      composer: controller.composer!,
      documentLayoutResolver: () =>
          _docLayoutKey.currentState as DocumentLayout,
    );

    _iosController ??= RichSuperEditorIosControlsController(
      editor: controller.editor!,
      documentLayoutResolver: () =>
          _docLayoutKey.currentState as DocumentLayout,
      operations: _richOps!,
      handleColor: editorControlsColor,
    );

    _androidController ??= SuperEditorAndroidControlsController(
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
                        const ImageAttachmentComponentBuilder(),
                        const FileAttachmentComponentBuilder(),
                        const RichLinkComponentBuilder(),
                        ...defaultComponentBuilders,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!widget.isReadOnly)
            NoteToolbar(
              editor: controller.editor!,
              composer: controller.composer!,
              onAttach: _onAttach,
            ),
        ],
      ),
    );
  }
}

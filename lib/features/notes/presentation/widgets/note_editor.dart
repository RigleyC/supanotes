library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/domain/attachment_model.dart';
import 'package:supanotes/features/notes/domain/attachment_nodes.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';
import 'package:supanotes/features/notes/presentation/note_stylesheet.dart';
import 'package:supanotes/features/notes/presentation/widgets/attachment_components.dart';
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
  final Future<AttachmentModel> Function(
    String noteId,
    String filePath,
    String mimeType,
  )? onUploadFile;

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

  Future<void> _onAttach({bool imageOnly = false}) async {
    if (widget.onUploadFile == null) return;
    if (_controller?.editor == null) return;

    final result = await FilePicker.platform.pickFiles(
      type: imageOnly ? FileType.image : FileType.any,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final path = picked.path;
    if (path == null) return;
    final mimeType = lookupMimeType(path) ?? 'application/octet-stream';
    final tempId = Editor.createNodeId();

    final isImage = mimeType.startsWith('image/');
    final placeholderNode = isImage
        ? ImageAttachmentNode(
            id: tempId,
            url: '',
            fileName: picked.name,
            metadata: {'isUploading': true},
          )
        : FileAttachmentNode(
            id: tempId,
            url: '',
            fileName: picked.name,
            mimeType: mimeType,
            fileSize: picked.size,
            metadata: {'isUploading': true},
          );

    _controller!.editor!.execute([
      InsertNodeAtCaretRequest(node: placeholderNode),
    ]);

    try {
      final attachment = await widget.onUploadFile!(widget.noteId, path, mimeType);
      final url = attachment.displayUrl ?? '';
      final DocumentNode finalNode = attachment.type == AttachmentType.image
          ? ImageAttachmentNode(
              id: attachment.id,
              url: url,
              fileName: attachment.fileName,
            )
          : FileAttachmentNode(
              id: attachment.id,
              url: url,
              fileName: attachment.fileName,
              mimeType: attachment.mimeType,
              fileSize: attachment.fileSize,
            );

      _controller!.editor!.execute([
        ReplaceNodeRequest(existingNodeId: tempId, newNode: finalNode),
      ]);
    } catch (_) {
      _controller!.editor!.execute([
        DeleteNodeRequest(nodeId: tempId),
      ]);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Falha ao enviar anexo')),
        );
      }
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
                        AttachmentComponentBuilder(editor: controller.editor!),
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
              onAttachFile: () => _onAttach(imageOnly: false),
              onAttachImage: () => _onAttach(imageOnly: true),
            ),
        ],
      ),
    );
  }
}

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
import 'package:supanotes/features/notes/domain/attachment_model.dart';
import 'package:supanotes/features/notes/domain/attachment_nodes.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';
import 'package:supanotes/features/notes/presentation/controllers/notes_providers.dart';
import 'package:supanotes/features/notes/presentation/note_stylesheet.dart';
import 'package:supanotes/features/notes/presentation/widgets/attachment_components.dart';
import 'package:supanotes/features/notes/presentation/widgets/custom_divider_component.dart';
import 'package:supanotes/features/notes/presentation/widgets/custom_task_component.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_link_tap_handler.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_toolbar.dart';
import 'package:supanotes/features/notes/presentation/widgets/rich_common_editor_operations.dart';
import 'package:supanotes/features/notes/presentation/widgets/rich_ios_controls_controller.dart';
import 'package:supanotes/features/notes/presentation/widgets/rich_keyboard_actions.dart';
import 'package:supanotes/features/notes/presentation/widgets/hashtag_suggestion_handler.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';

class NoteEditor extends ConsumerStatefulWidget {
  final String noteId;
  final String content;
  final Map<String, TaskModel> taskMetadata;
  final bool hideCompleted;
  final bool collapseImages;
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
    this.collapseImages = false,
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
  ConsumerState<NoteEditor> createState() => _NoteEditorState();
}

class _HashtagMatch {
  final String query;
  final String nodeId;
  final int tagStart;
  final int tagEnd;

  const _HashtagMatch({
    required this.query,
    required this.nodeId,
    required this.tagStart,
    required this.tagEnd,
  });
}

class _NoteEditorState extends ConsumerState<NoteEditor> {
  NoteEditorController? _controller;
  final _docLayoutKey = GlobalKey();
  RichSuperEditorIosControlsController? _iosController;
  SuperEditorAndroidControlsController? _androidController;
  RichCommonEditorOperations? _richOps;
  String _lastContent = '';
  bool _hasLocalEdits = false;

  final ValueNotifier<_HashtagMatch?> _hashtagMatch = ValueNotifier(null);

  late CustomTaskComponentBuilder _taskComponentBuilder;

  @override
  void initState() {
    super.initState();
    _lastContent = widget.content;
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
      _controller!.composer?.selectionNotifier.addListener(_updateHashtagMatch);
      _updateHashtagMatch();
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
      _controller?.composer?.selectionNotifier.removeListener(_updateHashtagMatch);
    }
    _hashtagMatch.dispose();
    _iosController?.dispose();
    _androidController?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _onDocumentChanged(DocumentChangeLog _) {
    _hasLocalEdits = true;
    _notifyContentChanged();
    _updateHashtagMatch();
  }

  _HashtagMatch? _computeHashtagMatch() {
    final composer = _controller?.composer;
    final editor = _controller?.editor;
    if (composer == null || editor == null) return null;

    final selection = composer.selection;
    if (selection == null || !selection.isCollapsed) return null;

    final position = selection.extent;
    final nodeId = position.nodeId;
    final node = editor.document.getNodeById(nodeId);
    if (node is! TextNode) return null;

    final text = node.text.toPlainText();
    final caretOffset = (position.nodePosition as TextNodePosition).offset;
    if (caretOffset == 0) return null;
    final textBeforeCaret = text.substring(0, caretOffset);
    final match = RegExp(r'#([^\s#]*)$').firstMatch(textBeforeCaret);
    if (match == null) return null;

    return _HashtagMatch(
      query: match.group(1)!,
      nodeId: node.id,
      tagStart: match.start,
      tagEnd: caretOffset,
    );
  }

  void _updateHashtagMatch() {
    _hashtagMatch.value = _computeHashtagMatch();
  }

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

      final existingNode = _controller!.editor!.document.getNodeById(tempId);
      if (existingNode == null) {
        return;
      }

      _controller!.editor!.execute([
        ReplaceNodeRequest(existingNodeId: tempId, newNode: finalNode),
      ]);
    } catch (_) {
      final existingNode = _controller!.editor!.document.getNodeById(tempId);
      if (existingNode != null) {
        _controller!.editor!.execute([
          DeleteNodeRequest(nodeId: tempId),
        ]);
      }

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
          ValueListenableBuilder<_HashtagMatch?>(
            valueListenable: _hashtagMatch,
            builder: (context, match, _) {
              if (match == null || widget.isReadOnly) return const SizedBox.shrink();
              return _NoteLinkSuggestions(
                match: match,
                currentNoteId: widget.noteId,
                onNoteSelected: _onSuggestionTap,
              );
            },
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

  void _onSuggestionTap(NoteModel note) {
    final match = _hashtagMatch.value;
    if (match == null || _controller?.editor == null) return;
    applyHashtagSuggestion(
      editor: _controller!.editor!,
      nodeId: match.nodeId,
      tagStartOffset: match.tagStart,
      tagEndOffset: match.tagEnd,
      note: note,
      onPersist: () => _controller?.persistSnapshotNow(),
    );
  }
}

class _NoteLinkSuggestions extends ConsumerWidget {
  final _HashtagMatch match;
  final String currentNoteId;
  final ValueChanged<NoteModel> onNoteSelected;

  const _NoteLinkSuggestions({
    required this.match,
    required this.currentNoteId,
    required this.onNoteSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(activeNotesProvider).asData?.value;
    if (notes == null) return const SizedBox.shrink();

    final suggestions = notes
        .where((n) =>
            n.id != currentNoteId &&
            n.title.toLowerCase().contains(match.query.toLowerCase()))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (suggestions.isEmpty) return const SizedBox.shrink();

    final chips = suggestions.take(10).map((note) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: () => onNoteSelected(note),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(
                note.title,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();

    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        itemBuilder: (_, i) => chips[i],
      ),
    );
  }
}

library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_delegate.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_provider.dart';
import 'package:supanotes/features/notes/presentation/note_stylesheet.dart';
import 'package:supanotes/features/notes/presentation/widgets/attachment_components.dart';
import 'package:supanotes/features/notes/presentation/widgets/custom_divider_component.dart';
import 'package:supanotes/features/notes/presentation/widgets/custom_task_component.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_editor_config.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_suggestion_overlay.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_link_tap_handler.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_toolbar.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';

class NoteEditor extends ConsumerStatefulWidget {
  final String noteId;
  final Map<String, TaskModel> taskMetadata;
  final bool hideCompleted;
  final bool collapseImages;
  final bool isReadOnly;
  final NoteEditorDelegate delegate;

  const NoteEditor({
    super.key,
    required this.noteId,
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
  EditorControls? _controls;
  Stylesheet? _cachedStylesheet;
  ColorScheme? _cachedColorScheme;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(noteEditorControllerProvider(widget.noteId));
    _controller!.addListener(_onControllerReady);
    _controller!.onHasContentChanged = (hasContent) {
      widget.delegate.onHasContentChanged?.call(hasContent);
    };
  }

  void _initControls() {
    if (_controls != null) return;
    final controller = _controller!;
    if (controller.editor == null || controller.composer == null) return;

    final editorControlsColor = Theme.of(context).colorScheme.primary;
    _controls = createEditorControls(
      editor: controller.editor!,
      composer: controller.composer!,
      documentLayoutResolver: () =>
          _docLayoutKey.currentState as DocumentLayout,
      handleColor: editorControlsColor,
    );
  }

  @override
  void didUpdateWidget(NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hideCompleted != oldWidget.hideCompleted) {
      setState(() {});
    }
  }

  void _onControllerReady() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerReady);
    _controller!.onHasContentChanged = null;
    _controls?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(noteEditorControllerProvider(widget.noteId));
    final controller = _controller;
    if (controller == null || !controller.hasDocument) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.document == null ||
        controller.editor == null ||
        controller.composer == null) {
      return const Center(child: CircularProgressIndicator());
    }

    _initControls();

    final theme = Theme.of(context);

    final topPadding = Scaffold.maybeOf(context)?.appBarMaxHeight ??
        (MediaQuery.paddingOf(context).top + kToolbarHeight);

    final docPadding = EdgeInsets.only(
      left: 24,
      right: 24,
      top: topPadding,
      bottom: 24,
    );

    if (_cachedStylesheet == null ||
        !identical(_cachedColorScheme, theme.colorScheme) ||
        _cachedStylesheet!.documentPadding != docPadding) {
      _cachedColorScheme = theme.colorScheme;
      _cachedStylesheet = noteStylesheet(
        context,
        documentPadding: docPadding,
      );
    }

    return Column(
        children: [
          Expanded(
            child: SuperEditorAndroidControlsScope(
              controller: _controls!.androidController,
              child: SuperEditorIosControlsScope(
                controller: _controls!.iosController,
                child: SuperEditor(
                  editor: controller.editor!,
                  focusNode: widget.isReadOnly ? null : controller.focusNode,
                  documentLayoutKey: _docLayoutKey,
                  stylesheet: _cachedStylesheet!,
                  selectionStyle: editorSelectionStyle(theme.colorScheme),
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
                  keyboardActions: editorKeyboardActions(),
                  componentBuilders: [
                    const CustomDividerComponentBuilder(),
                    CustomTaskComponentBuilder(
                      editor: controller.editor,
                      composer: controller.composer,
                      taskMetadataById: widget.taskMetadata,
                      hideCompleted: widget.hideCompleted,
                      onTaskLongPress: widget.isReadOnly
                          ? null
                          : (taskId) => widget.delegate.onTaskLongPress?.call(
                              widget.taskMetadata[taskId],
                              () async {},
                            ),
                      onTaskComplete: widget.delegate.onTaskComplete,
                      onTaskReopen: widget.delegate.onTaskReopen,
                      onRecurringTaskComplete: (taskId, nextDue) {
                        controller.completeRecurringTask(taskId, nextDue);
                        widget.delegate.onRecurringTaskComplete?.call(
                          taskId,
                          nextDue,
                        );
                      },
                    ),
                    AttachmentComponentBuilder(
                      editor: controller.editor!,
                      collapseImages: widget.collapseImages,
                    ),
                    ...defaultComponentBuilders,
                  ],
                ),
              ),
            ),
          ),
          if (!widget.isReadOnly)
            NoteSuggestionOverlay(
              editor: controller.editor!,
              composer: controller.composer!,
              currentNoteId: widget.noteId,
              onPersist: () async {},
            ),
          if (!widget.isReadOnly)
            NoteToolbar(
              editor: controller.editor!,
              composer: controller.composer!,
              onAttachFile: () =>
                  controller.pickAndAttachFile(imageOnly: false),
              onAttachImage: () =>
                  controller.pickAndAttachFile(imageOnly: true),
            ),
        ],
      );
  }
}

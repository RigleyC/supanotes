library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_controller.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_delegate.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_provider.dart';
import 'package:supanotes/features/notes/editor/presentation/note_desktop_stylesheet.dart';
import 'package:supanotes/features/notes/editor/presentation/note_mobile_stylesheet.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/desktop_editor_viewport.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/attachment_components.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/custom_divider_component.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/custom_task_component.dart';
import 'package:supanotes/core/utils/platform_utils.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/slash_command_overlay.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_editor_config.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_link_tap_handler.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_suggestion_overlay.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_toolbar.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/shared/theme/desktop_layout_tokens.dart';

class NoteEditor extends ConsumerStatefulWidget {
  final String noteId;
  final Map<String, TaskModel> taskMetadata;
  final bool hideCompleted;
  final bool collapseImages;
  final bool isReadOnly;
  final bool requestInitialFocus;
  final NoteEditorDelegate delegate;

  const NoteEditor({
    super.key,
    required this.noteId,
    required this.taskMetadata,
    this.hideCompleted = false,
    this.collapseImages = false,
    this.isReadOnly = false,
    this.requestInitialFocus = false,
    required this.delegate,
  });

  @override
  ConsumerState<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends ConsumerState<NoteEditor> {
  NoteEditorController? _controller;
  final SlashCommandController _slashCommandController =
      SlashCommandController();
  final _docLayoutKey = GlobalKey();
  EditorControls? _controls;
  Stylesheet? _cachedStylesheet;
  ColorScheme? _cachedColorScheme;
  bool? _cachedIsDesktop;

  CustomTaskComponentBuilder? _taskComponentBuilder;
  List<ComponentBuilder>? _componentBuilders;
  List<SuperEditorContentTapDelegateFactory>? _contentTapDelegateFactories;

  @override
  void initState() {
    super.initState();
  }

  void _initControls() {
    if (_controls != null) return;
    final controller = _controller!;

    final editorControlsColor = Theme.of(context).colorScheme.primary;
    _controls = createEditorControls(
      editor: controller.editor,
      composer: controller.composer,
      documentLayoutResolver: () =>
          _docLayoutKey.currentState as DocumentLayout,
      handleColor: editorControlsColor,
    );

    _initStableBuilders();
  }

  void _initStableBuilders() {
    if (_componentBuilders != null) return;
    final controller = _controller!;

    _contentTapDelegateFactories = [
      (editContext) => NoteLinkTapHandler(
        editContext.document,
        editContext.composer,
        allowExternalLinks: widget.isReadOnly,
        onNoteTap: (targetId) => context.push(AppRoutes.note(targetId)),
      ),
      if (!widget.isReadOnly) superEditorLaunchLinkTapHandlerFactory,
    ];

    _taskComponentBuilder = CustomTaskComponentBuilder(
      editor: controller.editor,
      composer: controller.composer,
      taskMetadataById: widget.taskMetadata,
      hideCompleted: widget.hideCompleted,
      onTaskLongPress: widget.isReadOnly
          ? null
          : widget.delegate.onTaskLongPress,
      onTaskComplete: widget.delegate.onTaskComplete,
      onTaskReopen: widget.delegate.onTaskReopen,
    );

    _componentBuilders = [
      const CustomDividerComponentBuilder(),
      _taskComponentBuilder!,
      AttachmentComponentBuilder(
        editor: controller.editor,
        collapseImages: widget.collapseImages,
      ),
      ...defaultComponentBuilders,
    ];
  }

  void _configureHiddenTaskEditing() {
    final controller = _controller;
    if (controller == null) return;

    controller.setHiddenTaskPredicate(
      (node) =>
          widget.hideCompleted &&
          node.isComplete &&
          !isRecurringTaskNode(node, widget.taskMetadata[node.id]),
    );
  }

  @override
  void didUpdateWidget(NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.hideCompleted != oldWidget.hideCompleted ||
        widget.taskMetadata != oldWidget.taskMetadata) {
      _configureHiddenTaskEditing();
    }

    if (widget.hideCompleted != oldWidget.hideCompleted ||
        widget.collapseImages != oldWidget.collapseImages ||
        widget.isReadOnly != oldWidget.isReadOnly) {
      if (widget.hideCompleted && !oldWidget.hideCompleted) {
        final selection = _controller?.composer.selection;
        final selectedNode = selection == null
            ? null
            : _controller?.editor.document.getNodeById(selection.extent.nodeId);
        if (selectedNode is TaskNode && selectedNode.isComplete) {
          _controller?.composer.clearSelection();
          _controller?.focusNode.unfocus();
        }
      }
      _componentBuilders = null;
      _contentTapDelegateFactories = null;
      _taskComponentBuilder = null;
    } else if (widget.taskMetadata != oldWidget.taskMetadata) {
      _taskComponentBuilder?.taskMetadataById = widget.taskMetadata;
    }
  }

  void _onControllerReady() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerReady);
    _controller?.onHasContentChanged = null;
    _slashCommandController.dispose();
    _controls?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(noteEditorSessionProvider(widget.noteId));

    return sessionAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(body: Center(child: Text('Erro: $error'))),
      data: (session) {
        final controller = session.controller;
        if (_controller != controller) {
          _controller?.removeListener(_onControllerReady);
          _controller = controller;
          _controller!.addListener(_onControllerReady);
          _controller!.onHasContentChanged = (hasContent) {
            widget.delegate.onHasContentChanged?.call(hasContent);
          };
          _configureHiddenTaskEditing();
        }

        _initControls();
        _initStableBuilders();

        final desktopLayout = DesktopEditorLayoutScope.maybeOf(context);
        final isDesktop = desktopLayout != null || isDesktopLayout(context);
        return LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width;
            final topPadding =
                Scaffold.maybeOf(context)?.appBarMaxHeight ??
                (MediaQuery.paddingOf(context).top + kToolbarHeight);
            final desktopDocumentPadding = desktopLayout?.documentPadding;
            final docPadding =
                desktopDocumentPadding ??
                (isDesktop
                    ? EdgeInsets.only(
                        left: desktopEditorSidePaddingForWidth(availableWidth),
                        right: desktopEditorSidePaddingForWidth(availableWidth),
                        top: DesktopLayoutTokens.editorTopPadding,
                        bottom:
                            DesktopLayoutTokens.editorBottomPaddingForHeight(
                              MediaQuery.sizeOf(context).height,
                            ),
                      )
                    : EdgeInsets.only(
                        left: 24,
                        right: 24,
                        top: topPadding,
                        bottom: widget.isReadOnly ? 24 : 140,
                      ));

            final theme = Theme.of(context);
            if (_cachedStylesheet == null ||
                !identical(_cachedColorScheme, theme.colorScheme) ||
                _cachedStylesheet!.documentPadding != docPadding ||
                _cachedIsDesktop != isDesktop) {
              _cachedColorScheme = theme.colorScheme;
              _cachedIsDesktop = isDesktop;
              _cachedStylesheet = isDesktop
                  ? desktopNoteStylesheet(context, documentPadding: docPadding)
                  : mobileNoteStylesheet(context, documentPadding: docPadding);
            }

            final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

            return Stack(
              children: [
                Positioned.fill(
                  child: SuperEditorAndroidControlsScope(
                    controller: _controls!.androidController,
                    child: SuperEditorIosControlsScope(
                      controller: _controls!.iosController,
                      child: TapRegion(
                        groupId: noteEditorToolbarTapRegionGroup,
                        child: SuperEditor(
                          editor: controller.editor,
                          focusNode: widget.isReadOnly
                              ? null
                              : controller.focusNode,
                          autofocus:
                              widget.requestInitialFocus && !widget.isReadOnly,
                          inputSource: TextInputSource.ime,
                          documentLayoutKey: _docLayoutKey,
                          stylesheet: _cachedStylesheet!,
                          selectionStyle: editorSelectionStyle(
                            theme.colorScheme,
                          ),
                          documentOverlayBuilders: [
                            ...defaultSuperEditorDocumentOverlayBuilders.where(
                              (builder) =>
                                  builder is! DefaultCaretOverlayBuilder,
                            ),
                            DefaultCaretOverlayBuilder(
                              caretStyle: CaretStyle(
                                color: theme.colorScheme.primary,
                                width: 2.5,
                              ),
                            ),
                          ],
                          contentTapDelegateFactories:
                              _contentTapDelegateFactories,
                          keyboardActions: editorKeyboardActions(
                            slashCommandController: widget.isReadOnly
                                ? null
                                : _slashCommandController,
                          ),
                          componentBuilders: _componentBuilders!,
                        ),
                      ),
                    ),
                  ),
                ),
                if (!widget.isReadOnly) ...[
                  Positioned.fill(
                    child: SlashCommandOverlay(
                      editor: controller.editor,
                      composer: controller.composer,
                      documentLayoutResolver: () =>
                          _docLayoutKey.currentState as DocumentLayout,
                      documentLayoutContextResolver: () =>
                          _docLayoutKey.currentContext,
                      controller: _slashCommandController,
                      focusNode: controller.focusNode,
                      onAttachFile: () =>
                          controller.pickAndAttachFile(imageOnly: false),
                      onAttachImage: () =>
                          controller.pickAndAttachFile(imageOnly: true),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: bottomInset,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isDesktop)
                          NoteSuggestionOverlay(
                            editor: controller.editor,
                            composer: controller.composer,
                            currentNoteId: widget.noteId,
                            onPersist: () async {},
                          ),
                        NoteToolbar(
                          editor: controller.editor,
                          composer: controller.composer,
                          focusNode: controller.focusNode,
                          onAttachFile: () =>
                              controller.pickAndAttachFile(imageOnly: false),
                          onAttachImage: () =>
                              controller.pickAndAttachFile(imageOnly: true),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

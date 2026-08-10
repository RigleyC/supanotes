library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_controller.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_delegate.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_open_options.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_provider.dart';
import 'package:supanotes/features/notes/editor/presentation/note_desktop_stylesheet.dart';
import 'package:supanotes/features/notes/editor/presentation/note_mobile_stylesheet.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/desktop_editor_viewport.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/desktop_selection_formatting_overlay.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/attachment_components.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/custom_divider_component.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/custom_task_component.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/hidden_task_trailing_tap_handler.dart';
import 'package:supanotes/core/utils/platform_utils.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/slash_command_overlay.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_editor_config.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_link_tap_handler.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_suggestion_overlay.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_toolbar.dart';
import 'package:supanotes/features/notes/editor/document/markdown_task_shortcut_plugin.dart';
import 'package:supanotes/features/notes/sharing/presentation/share_link_attachment_component.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/shared/theme/desktop_layout_tokens.dart';

class NoteEditor extends ConsumerStatefulWidget {
  final String noteId;
  final Map<String, TaskModel> taskMetadata;
  final bool hideCompleted;
  final bool collapseImages;
  final bool isReadOnly;
  final bool allowInternalNoteLinks;
  final NoteEditorAccessMode? sessionAccessMode;
  final String? shareLinkToken;
  final bool requestInitialFocus;
  final NoteEditorDelegate delegate;

  const NoteEditor({
    super.key,
    required this.noteId,
    required this.taskMetadata,
    this.hideCompleted = false,
    this.collapseImages = false,
    this.isReadOnly = false,
    this.allowInternalNoteLinks = true,
    this.sessionAccessMode,
    this.shareLinkToken,
    this.requestInitialFocus = false,
    required this.delegate,
  });

  bool get effectiveIsReadOnly => switch (sessionAccessMode) {
    NoteEditorAccessMode.readOnly => true,
    NoteEditorAccessMode.editable => false,
    null => isReadOnly,
  };

  @override
  ConsumerState<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends ConsumerState<NoteEditor> {
  NoteEditorController? _controller;
  final SlashCommandController _slashCommandController =
      SlashCommandController();
  final _docLayoutKey = GlobalKey();
  final _editorViewportKey = GlobalKey();
  final _selectionLayerLinks = SelectionLayerLinks();
  final _softwareKeyboardController = SoftwareKeyboardController();
  final _formattingToolbarOpen = ValueNotifier<bool>(false);
  late final MarkdownInlineUpstreamSyntaxPlugin _markdownInlinePlugin =
      MarkdownInlineUpstreamSyntaxPlugin();
  late final MarkdownTaskShortcutPlugin _markdownTaskPlugin =
      MarkdownTaskShortcutPlugin();
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
        allowInternalNoteLinks: widget.allowInternalNoteLinks,
        onNoteTap: (targetId) => context.push(AppRoutes.note(targetId)),
      ),
      if (!widget.effectiveIsReadOnly)
        (editContext) => HiddenTaskTrailingTapHandler(
          editContext: editContext,
          isHiddenTask: _isHiddenTask,
          openSoftwareKeyboard: () {
            if (_softwareKeyboardController.hasDelegate) {
              _softwareKeyboardController.open(viewId: View.of(context).viewId);
            }
          },
        ),
      if (!widget.effectiveIsReadOnly) superEditorAddEmptyParagraphTapHandlerFactory,
    ];

    _taskComponentBuilder = CustomTaskComponentBuilder(
      editor: controller.editor,
      composer: controller.composer,
      taskMetadataById: widget.taskMetadata,
      hideCompleted: widget.hideCompleted,
      readOnly: widget.effectiveIsReadOnly,
      onTaskLongPress: widget.effectiveIsReadOnly
          ? null
          : widget.delegate.onTaskLongPress,
      onTaskComplete: widget.delegate.onTaskComplete,
      onTaskReopen: widget.delegate.onTaskReopen,
    );

    _componentBuilders = [
      const CustomDividerComponentBuilder(),
      _taskComponentBuilder!,
      if (widget.effectiveIsReadOnly && widget.shareLinkToken != null)
        ShareLinkAttachmentComponentBuilder(token: widget.shareLinkToken!)
      else
        AttachmentComponentBuilder(
          editor: controller.editor,
          collapseImages: widget.collapseImages,
          readOnly: widget.effectiveIsReadOnly,
          allowInternalNoteLinks: widget.allowInternalNoteLinks,
          shareLinkToken: widget.shareLinkToken,
        ),
      ...defaultComponentBuilders,
    ];
  }

  void _configureHiddenTaskEditing() {
    final controller = _controller;
    if (controller == null) return;

    controller.setHiddenTaskPredicate(_isHiddenTask);
  }

  bool _isHiddenTask(TaskNode node) =>
      widget.hideCompleted &&
      node.isComplete &&
      !isRecurringTaskNode(node, widget.taskMetadata[node.id]);

  @override
  void didUpdateWidget(NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.hideCompleted != oldWidget.hideCompleted ||
        widget.taskMetadata != oldWidget.taskMetadata) {
      _configureHiddenTaskEditing();
    }

    if (widget.hideCompleted != oldWidget.hideCompleted ||
        widget.collapseImages != oldWidget.collapseImages ||
        widget.effectiveIsReadOnly != oldWidget.effectiveIsReadOnly ||
        widget.allowInternalNoteLinks != oldWidget.allowInternalNoteLinks ||
        widget.shareLinkToken != oldWidget.shareLinkToken) {
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
    _formattingToolbarOpen.dispose();
    _controls?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(switch (widget.sessionAccessMode) {
      NoteEditorAccessMode.readOnly => noteEditorReadOnlySessionProvider(
        widget.noteId,
      ),
      NoteEditorAccessMode.editable => noteEditorEditableSessionProvider(
        widget.noteId,
      ),
      null => noteEditorSessionProvider(widget.noteId),
    });

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

        if (!widget.effectiveIsReadOnly) {
          _initControls();
        }
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
                        bottom: widget.effectiveIsReadOnly ? 24 : 140,
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
                  child: DesktopSelectionFormattingOverlay(
                    enabled: isDesktop && !widget.effectiveIsReadOnly,
                    editor: controller.editor,
                    composer: controller.composer,
                    editorFocusNode: controller.focusNode,
                    selectionLayerLinks: _selectionLayerLinks,
                    viewportKey: _editorViewportKey,
                    child: widget.effectiveIsReadOnly
                        ? SuperReader(
                            key: ValueKey<(bool, bool)>((
                              isDesktop,
                              widget.effectiveIsReadOnly,
                            )),
                            editor: controller.editor,
                            documentLayoutKey: _docLayoutKey,
                            selectionLayerLinks: _selectionLayerLinks,
                            stylesheet: _cachedStylesheet!,
                            selectionStyle: editorSelectionStyle(
                              theme.colorScheme,
                            ),
                            componentBuilders: _componentBuilders!,
                            contentTapDelegateFactory: (readerContext) =>
                                NoteLinkTapHandler(
                                  readerContext.document,
                                  allowInternalNoteLinks:
                                      widget.allowInternalNoteLinks,
                                  onNoteTap: (targetId) =>
                                      context.push(AppRoutes.note(targetId)),
                                ),
                          )
                        : SuperEditorAndroidControlsScope(
                            controller: _controls!.androidController,
                            child: SuperEditorIosControlsScope(
                              controller: _controls!.iosController,
                              child: TapRegion(
                                groupId: noteEditorToolbarTapRegionGroup,
                                child: ValueListenableBuilder<bool>(
                                  valueListenable: _formattingToolbarOpen,
                                  builder:
                                      (
                                        context,
                                        formattingToolbarOpen,
                                        child,
                                      ) => SuperEditor(
                                        key: ValueKey<(bool, bool)>((
                                          isDesktop,
                                          widget.effectiveIsReadOnly,
                                        )),
                                        editor: controller.editor,
                                        plugins: isDesktop
                                            ? {
                                                _markdownInlinePlugin,
                                                _markdownTaskPlugin,
                                              }
                                            : const {},
                                        focusNode: controller.focusNode,
                                        autofocus: widget.requestInitialFocus,
                                        inputSource: TextInputSource.ime,
                                        softwareKeyboardController:
                                            _softwareKeyboardController,
                                        imePolicies: SuperEditorImePolicies(
                                          openKeyboardOnSelectionChange:
                                              !formattingToolbarOpen,
                                        ),
                                        documentLayoutKey: _docLayoutKey,
                                        selectionLayerLinks:
                                            _selectionLayerLinks,
                                        stylesheet: _cachedStylesheet!,
                                        selectionStyle: editorSelectionStyle(
                                          theme.colorScheme,
                                        ),
                                        documentOverlayBuilders: [
                                          ...defaultSuperEditorDocumentOverlayBuilders
                                              .where(
                                                (builder) =>
                                                    builder
                                                        is! DefaultCaretOverlayBuilder,
                                              ),
                                          DefaultCaretOverlayBuilder(
                                            caretStyle: CaretStyle(
                                              color: theme.colorScheme.primary,
                                              width: 1.5,
                                            ),
                                          ),
                                        ],
                                        contentTapDelegateFactories:
                                            _contentTapDelegateFactories,
                                        keyboardActions: editorKeyboardActions(
                                          slashCommandController:
                                              _slashCommandController,
                                        ),
                                        componentBuilders: _componentBuilders!,
                                      ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
                if (!widget.effectiveIsReadOnly) ...[
                  Positioned.fill(
                    child: SlashCommandOverlay(
                      editor: controller.editor,
                      composer: controller.composer,
                      selectionLayerLinks: _selectionLayerLinks,
                      viewportKey: _editorViewportKey,
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
                          softwareKeyboardController:
                              _softwareKeyboardController,
                          onFormattingModeChanged: (isOpen) =>
                              _formattingToolbarOpen.value = isOpen,
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

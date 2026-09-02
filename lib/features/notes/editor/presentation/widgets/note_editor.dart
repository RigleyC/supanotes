import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/notes/attachments/domain/attachment_delivery.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_controller.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_delegate.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_session.dart';
import 'package:supanotes/features/notes/editor/presentation/note_mobile_stylesheet.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/attachment_components.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/custom_divider_component.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/custom_list_item_component.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/custom_task_component.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/hidden_task_trailing_tap_handler.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_editor_config.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_link_tap_handler.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_suggestion_overlay.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_toolbar.dart';
import 'package:super_editor/super_editor.dart';

class NoteEditor extends StatefulWidget {
  const NoteEditor({
    required this.noteId,
    required this.session,
    required this.delegate,
    super.key,
    this.hideCompleted = false,
    this.collapseImages = false,
    this.attachmentDelivery,
    this.requestInitialFocus = false,
  });
  final String noteId;
  final NoteEditorSession session;
  final bool hideCompleted;
  final bool collapseImages;
  final AttachmentDelivery? attachmentDelivery;
  final bool requestInitialFocus;
  final NoteEditorDelegate delegate;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  NoteEditorController? _controller;
  final GlobalKey<State<StatefulWidget>> _docLayoutKey = GlobalKey();
  final _selectionLayerLinks = SelectionLayerLinks();
  final _softwareKeyboardController = SoftwareKeyboardController();
  final _isImeConnected = ValueNotifier<bool>(false);
  late final KeyboardPanelController<Object> _keyboardPanelController;
  EditorControls? _controls;
  Stylesheet? _cachedStylesheet;
  ColorScheme? _cachedColorScheme;

  CustomTaskComponentBuilder? _taskComponentBuilder;
  List<ComponentBuilder>? _componentBuilders;
  List<SuperEditorContentTapDelegateFactory>? _contentTapDelegateFactories;
  StreamSubscription<bool>? _captureSubscription;
  NoteEditorSession? _attachedSession;

  bool get _isReadOnly => !widget.session.captureLocalOperations;

  @override
  void initState() {
    super.initState();
    _keyboardPanelController = KeyboardPanelController<Object>(
      _softwareKeyboardController,
    );
    _attachSession(widget.session);
  }

  void _attachSession(NoteEditorSession session) {
    final controller = session.controller;
    if (identical(_attachedSession, session)) return;
    _controller?.removeListener(_onControllerReady);
    _controller?.focusNode.removeListener(_syncToolbarVisibility);
    _controller?.onHasContentChanged = null;
    unawaited(_captureSubscription?.cancel());
    _attachedSession = session;
    _controller = controller;
    _controller!.focusNode.addListener(_syncToolbarVisibility);
    _scheduleInitialToolbarSync();
    _captureSubscription = session.captureLocalOperationsChanges.listen((_) {
      if (!mounted) return;
      if (_isReadOnly) {
        _controls?.dispose();
        _controls = null;
      }
      _componentBuilders = null;
      _contentTapDelegateFactories = null;
      _taskComponentBuilder = null;
      setState(() {});
    });
    _controller!.addListener(_onControllerReady);
    _controller!.onHasContentChanged = (hasContent) {
      widget.delegate.onHasContentChanged?.call(hasContent);
    };
    _configureHiddenTaskEditing();
  }

  void _initControls() {
    if (_controls != null) return;
    final controller = _controller!;

    final editorControlsColor = Theme.of(context).colorScheme.primary;
    _controls = createEditorControls(
      editor: controller.editor,
      composer: controller.composer,
      documentLayoutResolver: () =>
          _docLayoutKey.currentState! as DocumentLayout,
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
        allowInternalNoteLinks: !_isReadOnly,
        onNoteTap: (targetId) => context.push(AppRoutes.note(targetId)),
      ),
      if (!_isReadOnly)
        (editContext) => HiddenTaskTrailingTapHandler(
          editContext: editContext,
          isHiddenTask: _isHiddenTask,
          openSoftwareKeyboard: () {
            if (_softwareKeyboardController.hasDelegate) {
              _softwareKeyboardController.open(viewId: View.of(context).viewId);
            }
          },
        ),
      if (!_isReadOnly) superEditorAddEmptyParagraphTapHandlerFactory,
    ];

    _taskComponentBuilder = CustomTaskComponentBuilder(
      hideCompleted: widget.hideCompleted,
      readOnly: _isReadOnly,
      onTaskLongPress: _isReadOnly ? null : widget.delegate.onTaskLongPress,
      onTaskComplete: widget.delegate.onTaskComplete,
      onTaskReopen: widget.delegate.onTaskReopen,
    );

    _componentBuilders = [
      const CustomDividerComponentBuilder(),
      _taskComponentBuilder!,
      const CustomListItemComponentBuilder(),
      AttachmentComponentBuilder(
        editor: controller.editor,
        collapseImages: widget.collapseImages,
        readOnly: _isReadOnly,
        allowInternalNoteLinks: !_isReadOnly,
        attachmentDelivery: widget.attachmentDelivery,
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
      widget.hideCompleted && node.isComplete && !isRecurringTaskNode(node);

  @override
  void didUpdateWidget(NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);

    _handleSessionUpdate(oldWidget);
    _handleHiddenTaskUpdate(oldWidget);
    _handleBuilderUpdate(oldWidget);
  }

  void _handleSessionUpdate(NoteEditor oldWidget) {
    if (widget.session == oldWidget.session) return;

    _controls?.dispose();
    _controls = null;
    _resetStableBuilders();
    _attachSession(widget.session);
  }

  void _handleHiddenTaskUpdate(NoteEditor oldWidget) {
    if (widget.hideCompleted != oldWidget.hideCompleted) {
      _configureHiddenTaskEditing();
    }
  }

  void _handleBuilderUpdate(NoteEditor oldWidget) {
    final builderInputsChanged =
        widget.hideCompleted != oldWidget.hideCompleted ||
        widget.collapseImages != oldWidget.collapseImages ||
        widget.attachmentDelivery != oldWidget.attachmentDelivery;

    if (!builderInputsChanged) return;

    if (widget.hideCompleted && !oldWidget.hideCompleted) {
      _clearSelectionFromCompletedTask();
    }
    _resetStableBuilders();
  }

  void _clearSelectionFromCompletedTask() {
    final selection = _controller?.composer.selection;
    final selectedNode = selection == null
        ? null
        : _controller?.editor.document.getNodeById(selection.extent.nodeId);
    if (selectedNode is TaskNode && selectedNode.isComplete) {
      _controller?.composer.clearSelection();
      _controller?.focusNode.unfocus();
    }
  }

  void _resetStableBuilders() {
    _componentBuilders = null;
    _contentTapDelegateFactories = null;
    _taskComponentBuilder = null;
  }

  void _onControllerReady() {
    if (!mounted) return;
    setState(() {});
  }

  void _syncToolbarVisibility() {
    if (!_keyboardPanelController.hasDelegate) return;
    final controller = _controller;
    if (controller == null) return;
    _keyboardPanelController.toolbarVisibility = controller.focusNode.hasFocus
        ? KeyboardToolbarVisibility.visible
        : KeyboardToolbarVisibility.hidden;
  }

  void _scheduleInitialToolbarSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncToolbarVisibility();
    });
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerReady);
    _controller?.focusNode.removeListener(_syncToolbarVisibility);
    _controller?.onHasContentChanged = null;
    unawaited(_captureSubscription?.cancel());
    _softwareKeyboardController.detach();
    _keyboardPanelController.dispose();
    _isImeConnected.dispose();
    _controls?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.session.controller;

    if (!_isReadOnly) {
      _initControls();
    }
    _initStableBuilders();

    return LayoutBuilder(
      builder: (context, constraints) {
        const docPadding = EdgeInsets.only(
          left: 24,
          right: 24,
          bottom: 24,
        );

        final theme = Theme.of(context);
        if (_cachedStylesheet == null ||
            !identical(_cachedColorScheme, theme.colorScheme) ||
            _cachedStylesheet!.documentPadding != docPadding) {
          _cachedColorScheme = theme.colorScheme;
          _cachedStylesheet = mobileNoteStylesheet(
            context,
            documentPadding: docPadding,
          );
        }

        if (_isReadOnly) {
          return SuperReader(
            key: ValueKey<bool>(_isReadOnly),
            editor: controller.editor,
            documentLayoutKey: _docLayoutKey,
            selectionLayerLinks: _selectionLayerLinks,
            stylesheet: _cachedStylesheet,
            selectionStyle: editorSelectionStyle(theme.colorScheme),
            componentBuilders: _componentBuilders,
            contentTapDelegateFactory: (readerContext) => NoteLinkTapHandler(
              readerContext.document,
              allowInternalNoteLinks: !_isReadOnly,
              onNoteTap: (targetId) => context.push(AppRoutes.note(targetId)),
            ),
          );
        }

        return KeyboardPanelScaffold<Object>(
          controller: _keyboardPanelController,
          isImeConnected: _isImeConnected,
          contentBuilder: (context, _) => PopScope(
            child: Column(
              children: [
                Expanded(
                  child: SuperEditorAndroidControlsScope(
                    controller: _controls!.androidController,
                    child: SuperEditorIosControlsScope(
                      controller: _controls!.iosController,
                      child: TapRegion(
                        groupId: noteEditorToolbarTapRegionGroup,
                        child: SuperEditor(
                          key: ValueKey<bool>(_isReadOnly),
                          editor: controller.editor,
                          focusNode: controller.focusNode,
                          autofocus: widget.requestInitialFocus,
                          inputSource: TextInputSource.ime,
                          softwareKeyboardController:
                              _softwareKeyboardController,
                          isImeConnected: _isImeConnected,
                          documentLayoutKey: _docLayoutKey,
                          selectionLayerLinks: _selectionLayerLinks,
                          stylesheet: _cachedStylesheet,
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
                                width: 1.5,
                              ),
                            ),
                          ],
                          contentTapDelegateFactories:
                              _contentTapDelegateFactories,
                          keyboardActions: editorKeyboardActions(),
                          componentBuilders: _componentBuilders,
                        ),
                      ),
                    ),
                  ),
                ),
                NoteSuggestionOverlay(
                  editor: controller.editor,
                  composer: controller.composer,
                  currentNoteId: widget.noteId,
                  onPersist: () async {},
                ),
              ],
            ),
          ),
          toolbarBuilder: (context, _) => NoteToolbar(
            editor: controller.editor,
            composer: controller.composer,
            onAttachFile: controller.pickAndAttachFile,
            onAttachImage: () => controller.pickAndAttachFile(imageOnly: true),
          ),
          keyboardPanelBuilder: (_, _) => const SizedBox.shrink(),
        );
      },
    );
  }
}

library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/notes/domain/note_session_coordinator.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_delegate.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_provider.dart';
import 'package:supanotes/features/notes/presentation/note_stylesheet.dart';
import 'package:supanotes/features/notes/presentation/widgets/attachment_components.dart';
import 'package:supanotes/features/notes/presentation/widgets/custom_divider_component.dart';
import 'package:supanotes/features/notes/presentation/widgets/custom_task_component.dart';
import 'package:supanotes/core/utils/platform_utils.dart';
import 'package:supanotes/features/notes/presentation/widgets/slash_command_overlay.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_editor_config.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_link_tap_handler.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_suggestion_overlay.dart';
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
  final SlashCommandController _slashCommandController =
      SlashCommandController();
  final _docLayoutKey = GlobalKey();
  EditorControls? _controls;
  Stylesheet? _cachedStylesheet;
  ColorScheme? _cachedColorScheme;

  CustomTaskComponentBuilder? _taskComponentBuilder;
  List<ComponentBuilder>? _componentBuilders;
  List<SuperEditorContentTapDelegateFactory>? _contentTapDelegateFactories;
  bool _didRequestInitialFocus = false;

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

    _contentTapDelegateFactories = widget.isReadOnly
        ? null
        : [
            (editContext) => NoteLinkTapHandler(
              editContext.document,
              editContext.composer,
              onNoteTap: (targetId) => context.push(AppRoutes.note(targetId)),
            ),
            superEditorLaunchLinkTapHandlerFactory,
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

  @override
  void didUpdateWidget(NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.hideCompleted != oldWidget.hideCompleted ||
        widget.collapseImages != oldWidget.collapseImages ||
        widget.isReadOnly != oldWidget.isReadOnly) {
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
        final status = ref
            .watch(noteEditorSessionStatusProvider(widget.noteId))
            .maybeWhen(data: (value) => value, orElse: () => null);
        final controller = session.controller;
        if (_controller != controller) {
          _controller?.removeListener(_onControllerReady);
          _didRequestInitialFocus = false;
          _controller = controller;
          _controller!.addListener(_onControllerReady);
          _controller!.onHasContentChanged = (hasContent) {
            widget.delegate.onHasContentChanged?.call(hasContent);
          };
          _requestInitialFocus(controller);
        }

        _initControls();
        _initStableBuilders();

        final theme = Theme.of(context);
        final topPadding =
            Scaffold.maybeOf(context)?.appBarMaxHeight ??
            (MediaQuery.paddingOf(context).top + kToolbarHeight);
        final docPadding = EdgeInsets.only(
          left: 24,
          right: 24,
          top: topPadding,
          bottom: widget.isReadOnly ? 24 : 140,
        );

        final isDesktop = isDesktopPlatform() || isDesktopLayout(context);

        if (_cachedStylesheet == null ||
            !identical(_cachedColorScheme, theme.colorScheme) ||
            _cachedStylesheet!.documentPadding != docPadding) {
          _cachedColorScheme = theme.colorScheme;
          _cachedStylesheet = noteStylesheet(
            context,
            documentPadding: docPadding,
            isDesktop: isDesktop,
          );
        }

        final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

        return Stack(
          children: [
            Positioned.fill(
              child: SuperEditorAndroidControlsScope(
                controller: _controls!.androidController,
                child: SuperEditorIosControlsScope(
                  controller: _controls!.iosController,
                  child: SuperEditor(
                    editor: controller.editor,
                    focusNode: widget.isReadOnly ? null : controller.focusNode,
                    documentLayoutKey: _docLayoutKey,
                    stylesheet: _cachedStylesheet!,
                    selectionStyle: editorSelectionStyle(theme.colorScheme),
                    documentOverlayBuilders: [
                      DefaultCaretOverlayBuilder(
                        caretStyle: CaretStyle(
                          color: theme.colorScheme.primary,
                          width: 2.5,
                        ),
                      ),
                    ],
                    contentTapDelegateFactories: _contentTapDelegateFactories,
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
              if (!isDesktop)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: bottomInset,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      NoteSuggestionOverlay(
                        editor: controller.editor,
                        composer: controller.composer,
                        currentNoteId: widget.noteId,
                        onPersist: () async {},
                      ),
                      NoteToolbar(
                        editor: controller.editor,
                        composer: controller.composer,
                        onAttachFile: () =>
                            controller.pickAndAttachFile(imageOnly: false),
                        onAttachImage: () =>
                            controller.pickAndAttachFile(imageOnly: true),
                      ),
                    ],
                  ),
                ),
            ],
            if (status == NoteSessionStatus.syncing ||
                status == NoteSessionStatus.syncError ||
                status == NoteSessionStatus.error)
              Positioned(
                top: 8,
                left: 16,
                right: 16,
                child: _NoteSessionStatusBanner(status: status!),
              ),
          ],
        );
      },
    );
  }

  void _requestInitialFocus(NoteEditorController controller) {
    if (_didRequestInitialFocus || widget.isReadOnly) return;
    if (controller.document.nodeCount != 1) return;
    final node = controller.document.first;
    if (node is! TextNode || node.text.toPlainText().isNotEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didRequestInitialFocus || widget.isReadOnly) return;
      if (controller.document.nodeCount != 1) return;
      final currentNode = controller.document.first;
      if (currentNode is! TextNode ||
          currentNode.text.toPlainText().isNotEmpty) {
        return;
      }

      final position = DocumentPosition(
        nodeId: currentNode.id,
        nodePosition: TextNodePosition(
          offset: currentNode.text.toPlainText().length,
        ),
      );
      controller.editor.execute([
        ChangeSelectionRequest(
          DocumentSelection.collapsed(position: position),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction,
        ),
      ]);
      controller.focusNode.requestFocus();
      _didRequestInitialFocus = true;
    });
  }
}

class _NoteSessionStatusBanner extends StatelessWidget {
  const _NoteSessionStatusBanner({required this.status});

  final NoteSessionStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isError =
        status == NoteSessionStatus.error ||
        status == NoteSessionStatus.syncError;
    return Align(
      alignment: Alignment.topCenter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isError
              ? theme.colorScheme.errorContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          boxShadow: kElevationToShadow[1],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isError)
                Icon(
                  Icons.sync_problem,
                  size: 18,
                  color: theme.colorScheme.onErrorContainer,
                )
              else
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                status == NoteSessionStatus.syncError
                    ? 'Sem conexao. Alteracoes pendentes.'
                    : isError
                    ? 'Sincronizacao pausada'
                    : 'Sincronizando',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: isError
                      ? theme.colorScheme.onErrorContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

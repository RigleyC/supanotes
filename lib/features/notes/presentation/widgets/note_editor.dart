library;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';
import 'package:supanotes/features/notes/presentation/note_stylesheet.dart';
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
  final String? title;
  final Map<String, TaskModel> taskMetadata;
  final bool hideCompleted;
  final SnapshotSave snapshotSave;
  final EmptyNoteExit? emptyNoteExit;
  final ValueChanged<bool>? onHasContentChanged;
  final void Function(
    String taskId,
    Future<void> Function() flushSnapshot,
  )? onTaskLongPress;

  const NoteEditor({
    super.key,
    required this.noteId,
    required this.content,
    this.title,
    required this.taskMetadata,
    this.hideCompleted = false,
    required this.snapshotSave,
    this.emptyNoteExit,
    this.onHasContentChanged,
    this.onTaskLongPress,
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

  @override
  void initState() {
    super.initState();
    _controller = NoteEditorController(
      snapshotSave: widget.snapshotSave,
      emptyNoteExit: widget.emptyNoteExit,
    );
    _controller!.bind(widget.noteId);
    _controller!.init(content: widget.content);
    _controller!.document?.addListener(_onDocumentChanged);
    _notifyContentChanged();
  }

  @override
  void dispose() {
    _controller?.document?.removeListener(_onDocumentChanged);
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
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
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
                      focusNode: controller.focusNode,
                      documentLayoutKey: _docLayoutKey,
                      stylesheet: noteStylesheet(context),
                      keyboardActions: buildRichKeyboardActions(
                        baseActions:
                            defaultTargetPlatform == TargetPlatform.iOS ||
                                    defaultTargetPlatform ==
                                        TargetPlatform.android
                                ? defaultImeKeyboardActions
                                : defaultKeyboardActions,
                      ),
                      componentBuilders: [
                        const CustomDividerComponentBuilder(),
                        ...defaultComponentBuilders,
                        CustomTaskComponentBuilder(
                          controller.editor!,
                          taskMetadataById: widget.taskMetadata,
                          hideCompleted: widget.hideCompleted,
                          onTaskLongPress: (taskId) =>
                              widget.onTaskLongPress?.call(
                                taskId,
                                () => controller.persistSnapshotNow(),
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          NoteToolbar(
            editor: controller.editor!,
            composer: controller.composer!,
          ),
        ],
      ),
    );
  }
}

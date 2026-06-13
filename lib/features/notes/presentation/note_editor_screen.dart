library;

import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_toolbar.dart';
import 'package:supanotes/features/notes/presentation/widgets/custom_task_component.dart';
import 'package:supanotes/features/notes/presentation/note_stylesheet.dart';
import 'package:supanotes/features/notes/presentation/widgets/rich_keyboard_actions.dart';
import 'package:supanotes/features/notes/presentation/widgets/rich_ios_controls_controller.dart';
import 'package:supanotes/features/notes/presentation/widgets/rich_common_editor_operations.dart';
import 'package:supanotes/features/tasks/data/tasks_repository.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_actions_sheet.dart';
import 'package:supanotes/shared/theme/app_typography.dart';

final noteProvider = StreamProvider.autoDispose.family<NoteModel?, String>((
  ref,
  id,
) {
  return ref.watch(notesRepositoryProvider).watchNoteById(id);
});

class NoteEditorScreen extends ConsumerStatefulWidget {
  final String noteId;

  const NoteEditorScreen({super.key, required this.noteId});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  NoteEditorController? _controller;
  final _docLayoutKey = GlobalKey();
  SuperEditorIosControlsController? _iosController;
  SuperEditorAndroidControlsController? _androidController;

  NoteEditorController _controllerOrCreate() {
    if (_controller != null) return _controller!;
    final repo = ref.read(notesRepositoryProvider);
    return _controller = NoteEditorController(
      snapshotSave: (noteId, title, markdown, tasks) =>
          defaultSnapshotSave(repo, noteId, title, markdown, tasks),
      emptyNoteExit: (noteId) => defaultEmptyNoteExit(repo, noteId),
    );
  }

  Future<void> _openTaskActions(
    NoteEditorController controller,
    String taskId,
  ) async {
    await controller.persistSnapshotNow();
    if (!mounted) return;

    ref.invalidate(tasksByNoteStreamProvider(widget.noteId));
    final freshTasks = await ref.read(
      tasksByNoteStreamProvider(widget.noteId).future,
    );
    final freshMap = {for (final t in freshTasks) t.id: t};
    final task = freshMap[taskId];
    if (task == null) return;

    if (!mounted) return;
    await TaskActionsSheet.show(context, task: task);
  }

  @override
  void dispose() {
    _iosController?.dispose();
    _androidController?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controllerOrCreate();
    controller.bind(widget.noteId);

    final asyncValue = ref.watch(noteProvider(widget.noteId));

    if (controller.document == null) {
      dev.log(
        '[NoteEditor] noteId=${widget.noteId}, asyncValue=${asyncValue.runtimeType}, '
        'hasData=${asyncValue.hasValue}, isLoading=${asyncValue.isLoading}',
        name: 'NoteEditor',
      );
      if (asyncValue.isLoading) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (asyncValue.hasError) {
        return Scaffold(
          body: Center(child: Text('Error: ${asyncValue.error}')),
        );
      }
      final note = asyncValue.asData?.value;
      if (note == null) {
        return const Scaffold(body: Center(child: Text('Nota nao encontrada')));
      }
      controller.init(content: note.content, title: note.title);
    }

    if (controller.document == null ||
        controller.editor == null ||
        controller.composer == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    _iosController ??= RichSuperEditorIosControlsController(
      editor: controller.editor!,
      documentLayoutResolver: () => _docLayoutKey.currentState as DocumentLayout,
    );

    _androidController ??= SuperEditorAndroidControlsController(
      toolbarBuilder: (overlayContext, mobileToolbarKey, focalPoint) => defaultAndroidEditorToolbarBuilder(
        overlayContext,
        mobileToolbarKey,
        RichCommonEditorOperations(
          editor: controller.editor!,
          document: controller.editor!.document,
          composer: controller.composer!,
          documentLayoutResolver: () => _docLayoutKey.currentState as DocumentLayout,
        ),
        SuperEditorAndroidControlsScope.rootOf(overlayContext),
        controller.composer!.selectionNotifier,
        focalPoint,
      ),
    );

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () => controller.focusNode?.unfocus(),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: AnimatedPadding(
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
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: controller.titleController,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            filled: false,
                            contentPadding: EdgeInsets.zero,
                            hintText: 'Sem titulo',
                          ),
                          style: AppTypography.textTheme.headlineMedium
                              ?.copyWith(
                                color:
                                    Theme.of(context).colorScheme.onSurface,
                              ),
                        ),
                      ),
                    ),
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
                            baseActions: defaultTargetPlatform == TargetPlatform.iOS ||
                                    defaultTargetPlatform == TargetPlatform.android
                                ? defaultImeKeyboardActions
                                : defaultKeyboardActions,
                          ),
                          componentBuilders: [
                            ...defaultComponentBuilders,
                            CustomTaskComponentBuilder(
                              controller.editor!,
                              focusNode: controller.focusNode,
                              onTaskLongPress: (taskId) =>
                                  _openTaskActions(controller, taskId),
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
        ),
      ),
    );
  }
}

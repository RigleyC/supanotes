library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:follow_the_leader/follow_the_leader.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';
import 'package:supanotes/features/notes/presentation/controllers/notes_providers.dart';
import 'package:supanotes/features/agent/domain/destination_type.dart';
import 'package:supanotes/features/notes/presentation/widgets/inbox_organize_sheet.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_toolbar.dart';
import 'package:supanotes/features/notes/presentation/widgets/custom_task_component.dart';
import 'package:supanotes/features/notes/presentation/note_stylesheet.dart';
import 'package:supanotes/features/tasks/data/tasks_repository.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_actions_sheet.dart';
import 'package:supanotes/shared/theme/app_typography.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  NoteEditorController? _controller;
  String? _inboxNoteId;
  final _docLayoutKey = GlobalKey();
  late final SuperEditorIosControlsController _iosController;
  CommonEditorOperations? _commonOps;

  NoteEditorController _controllerOrCreate() =>
      _controller ??= NoteEditorController(
        editableTitle: true,
        snapshotSave: (noteId, title, markdown, tasks) =>
            defaultSnapshotSave(ref, noteId, title, markdown, tasks),
      );

  @override
  void initState() {
    super.initState();
    _iosController = SuperEditorIosControlsController(
      toolbarBuilder: _buildIosToolbar,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(notesRepositoryProvider).ensureInbox());
    });
  }

  void _ensureCommonOps() {
    if (_commonOps != null) return;
    final ctrl = _controller;
    if (ctrl == null || ctrl.editor == null || ctrl.composer == null) return;
    _commonOps = CommonEditorOperations(
      editor: ctrl.editor!,
      document: ctrl.editor!.document,
      composer: ctrl.composer!,
      documentLayoutResolver: () => _docLayoutKey.currentState as DocumentLayout,
    );
  }

  Widget _buildIosToolbar(BuildContext context, Key toolbarKey, LeaderLink focalPoint) {
    _ensureCommonOps();
    final ops = _commonOps;
    if (ops == null) return const SizedBox();

    return iOSSystemPopoverEditorToolbarWithFallbackBuilder(
      context,
      toolbarKey,
      focalPoint,
      ops,
      SuperEditorIosControlsScope.rootOf(context),
    );
  }

  Future<void> _openTaskActions(
    NoteEditorController controller,
    String taskId,
  ) async {
    await controller.persistSnapshotNow();
    if (!mounted) return;

    final noteId = _inboxNoteId;
    if (noteId == null) return;

    ref.invalidate(tasksByNoteStreamProvider(noteId));
    final freshTasks = await ref.read(tasksByNoteStreamProvider(noteId).future);
    final freshMap = {for (final t in freshTasks) t.id: t};
    final task = freshMap[taskId];
    if (task == null) return;

    if (!mounted) return;
    await TaskActionsSheet.show(context, task: task);
  }

  @override
  void dispose() {
    _iosController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onOrganizePressed() async {
    final result = await showInboxOrganizeSheet(context);
    if (!mounted || result == null) return;

    final created = result.items
        .where(
          (i) => i.accepted && i.destinationType == DestinationType.newNote,
        )
        .length;
    final moved = result.items
        .where(
          (i) =>
              i.accepted && i.destinationType == DestinationType.existingNote,
        )
        .length;
    final kept = result.items
        .where((i) => i.accepted && i.destinationType == DestinationType.keep)
        .length;

    AppMessenger.showSuccess(
      context,
      '$created nota(s) criada(s), $moved atualizada(s), $kept mantida(s)',
    );
  }

  @override
  Widget build(BuildContext context) {
    // Incondicional: o Riverpod exige que ref.watch seja chamado em
    // todo build() para manter a assinatura viva.
    final asyncValue = ref.watch(inboxProvider);
    final controller = _controllerOrCreate();

    if (controller.document == null) {
      if (asyncValue.isLoading) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (asyncValue.hasError) {
        return Scaffold(
          body: Center(child: Text('Error: ${asyncValue.error}')),
        );
      }
      final inbox = asyncValue.asData?.value;
      if (inbox != null) {
        controller.bind(inbox.id);
        controller.init(content: inbox.content, title: inbox.title);
      }
    }

    if (controller.document == null ||
        controller.editor == null ||
        controller.composer == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final hasContent = controller.document!.isNotEmpty;
    final inboxId = asyncValue.asData?.value?.id;
    _inboxNoteId = inboxId;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await controller.flushBeforePop();
        if (!context.mounted) return;
        context.pop();
      },
      child: Scaffold(
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
                              hintText: 'Sem título',
                            ),
                            style: AppTypography.textTheme.headlineMedium
                                ?.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                          ),
                        ),
                      ),
                      SuperEditorIosControlsScope(
                        controller: _iosController,
                        child: SuperEditor(
                    editor: controller.editor!,
                    focusNode: controller.focusNode,
                    documentLayoutKey: _docLayoutKey,
                    stylesheet: noteStylesheet(context),
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
        floatingActionButton: _buildOrganizeFab(hasContent),
      ),
    );
  }

  Widget? _buildOrganizeFab(bool show) {
    if (!show) return null;
    return FloatingActionButton(
      onPressed: _onOrganizePressed,
      child: const Icon(Icons.auto_awesome),
    );
  }
}

library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';
import 'package:supanotes/features/notes/presentation/controllers/notes_providers.dart';
import 'package:supanotes/features/agent/domain/destination_type.dart';
import 'package:supanotes/features/notes/presentation/widgets/inbox_organize_sheet.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_toolbar.dart';
import 'package:supanotes/features/notes/presentation/widgets/custom_task_component.dart';
import 'package:supanotes/features/tasks/data/tasks_repository.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
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

  Map<String, TaskModel> _taskMapForInbox(String? noteId) {
    if (noteId == null) return const <String, TaskModel>{};
    return ref
        .watch(tasksByNoteStreamProvider(noteId))
        .maybeWhen(
          data: (tasks) => {for (final task in tasks) task.id: task},
          orElse: () => const <String, TaskModel>{},
        );
  }

  NoteEditorController _controllerOrCreate() =>
      _controller ??= NoteEditorController(
        editableTitle: true,
        snapshotSave: (noteId, title, markdown, tasks) =>
            defaultSnapshotSave(ref, noteId, title, markdown, tasks),
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(notesRepositoryProvider).ensureInbox());
    });
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
    final taskMetadataById = _taskMapForInbox(inboxId);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await controller.flushBeforePop();
        if (!context.mounted) return;
        context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: TextField(
            controller: controller.titleController,
            decoration: const InputDecoration(
              border: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.zero,
              hintText: 'Sem título',
            ),
            style: AppTypography.textTheme.headlineMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: SuperEditor(
                editor: controller.editor!,
                focusNode: controller.focusNode,
                stylesheet: defaultStylesheet.copyWith(
                  documentPadding: EdgeInsets.zero,
                ),
                componentBuilders: [
                  ...defaultComponentBuilders,
                  CustomTaskComponentBuilder(
                    controller.editor!,
                    taskMetadataById: taskMetadataById,
                    onTaskLongPress: (taskId) =>
                        _openTaskActions(controller, taskId),
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

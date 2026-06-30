import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/features/agent/domain/destination_type.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart'
    show defaultSnapshotSave;
import 'package:supanotes/features/notes/presentation/controllers/note_editor_delegate.dart';
import 'package:supanotes/features/notes/presentation/controllers/notes_providers.dart'
    show inboxProvider, noteWithTasksProvider;
import 'package:supanotes/features/notes/presentation/widgets/inbox_organize_sheet.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_editor.dart';
import 'package:supanotes/features/tasks/data/tasks_repository.dart'
    show tasksRepositoryProvider;
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_sheet.dart'
    show TaskMetadataSheet;
import 'package:supanotes/shared/widgets/adaptive_sliver_nav_bar.dart'
    show AdaptiveSliverNavBar;
import 'package:supanotes/features/tasks/presentation/controllers/task_snackbar_helper.dart'
    show TaskSnackBarHelper;
import 'package:supanotes/shared/widgets/app_snackbar.dart'
    show AppMessenger;

/// Route companion for the top-level Inbox tab.
///
/// The note that is edited here is the single inbox row; on first use the
/// repository ensures it is created lazily.
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  bool _hasContent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(notesRepositoryProvider).ensureInbox());
    });
  }

  Future<void> _openTaskActions(
    TaskModel? task,
    Future<void> Function() flushSnapshot,
  ) async {
    await flushSnapshot();
    if (!mounted || task == null) return;

    await TaskMetadataSheet.show(context, noteId: task.noteId, task: task);
  }

  Future<void> _onOrganizePressed() async {
    final result = await showInboxOrganizeSheet(context);
    if (!mounted || result == null) return;

    final created = result.items
        .where((i) => i.accepted && i.destinationType == DestinationType.newNote)
        .length;
    final moved = result.items
        .where((i) =>
            i.accepted && i.destinationType == DestinationType.existingNote)
        .length;
    final kept = result.items
        .where((i) => i.accepted && i.destinationType == DestinationType.keep)
        .length;

    AppMessenger.showSuccess(
      '$created nota(s) criada(s), $moved atualizada(s), $kept mantida(s)',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ref.watch(inboxProvider).when(
      data: (inbox) {
        if (inbox == null) {
          return const Scaffold(
            body: Center(child: Text('Inbox not found')),
          );
        }
        return _buildEditor(inbox);
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        body: Center(child: Text('Error: $error')),
      ),
    );
  }

  Widget _buildEditor(NoteModel inbox) {
    return ref.watch(noteWithTasksProvider(inbox.id)).when(
      data: (noteWithTasks) {
        final tasksMap = noteWithTasks.taskById;
        final repo = ref.read(notesRepositoryProvider);

        return Scaffold(
          resizeToAvoidBottomInset: false,
          body: CustomScrollView(
            slivers: [
              AdaptiveSliverNavBar(
                title: Text(inbox.title),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.check),
                    onPressed: () =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                  ),
                ],
              ),
              SliverFillRemaining(
                hasScrollBody: true,
                child: NoteEditor(
                  noteId: inbox.id,
                  content: inbox.content,
                  taskMetadata: tasksMap,
                  delegate: NoteEditorDelegate(
                    snapshotSave: (noteId, markdown, tasks) =>
                        defaultSnapshotSave(repo, noteId, markdown, tasks),
                    onHasContentChanged: (hasContent) {
                      if (mounted) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            setState(() => _hasContent = hasContent);
                          }
                        });
                      }
                    },
                    onTaskLongPress: (task, flushSnapshot) =>
                        _openTaskActions(task, flushSnapshot),
                    onTaskComplete: (taskId) =>
                        TaskSnackBarHelper.completeTaskWithFeedback(
                      onComplete: () =>
                          ref.read(tasksRepositoryProvider).completeTask(taskId),
                      onUndo: () =>
                          ref.read(tasksRepositoryProvider).reopenTask(taskId),
                    ),
                    onTaskReopen: (taskId) =>
                        ref.read(tasksRepositoryProvider).reopenTask(taskId),
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: _hasContent ? _buildOrganizeFab : null,
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        body: Center(child: Text('Error: $error')),
      ),
    );
  }

  Widget? get _buildOrganizeFab {
    return FloatingActionButton(
      onPressed: _onOrganizePressed,
      child: const Icon(Icons.auto_awesome),
    );
  }
}

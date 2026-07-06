import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/features/agent/domain/destination_type.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_delegate.dart';
import 'package:supanotes/features/notes/presentation/controllers/notes_providers.dart'
    show inboxProvider, noteWithTasksProvider, noteNodesProvider;
import 'package:supanotes/features/notes/presentation/widgets/inbox_organize_sheet.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_editor.dart';
import 'package:supanotes/features/tasks/data/tasks_repository.dart'
    show tasksRepositoryProvider;
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_sheet.dart'
    show TaskMetadataSheet;
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_snackbar_helper.dart'
    show TaskSnackBarHelper;
import 'package:supanotes/shared/widgets/app_snackbar.dart' show AppMessenger;

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

  Widget _fallbackScaffold(Widget child) =>
      AdaptiveScaffold(body: SafeArea(child: Center(child: child)));

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
      '$created nota(s) criada(s), $moved atualizada(s), $kept mantida(s)',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ref
        .watch(inboxProvider)
        .when(
          data: (inbox) {
            if (inbox == null) {
              return _fallbackScaffold(const Text('Inbox not found'));
            }
            return _buildEditor(inbox);
          },
          loading: () =>
              _fallbackScaffold(const CircularProgressIndicator()),
          error: (error, _) =>
              _fallbackScaffold(Text('Error: $error')),
        );
  }

  Widget _buildEditor(NoteModel inbox) {
    final nodesAsync = ref.watch(noteNodesProvider(inbox.id));
    final noteWithTasksAsync = ref.watch(noteWithTasksProvider(inbox.id));

    return nodesAsync.when(
      data: (nodes) {
        return noteWithTasksAsync.when(
          data: (noteWithTasks) {
            final tasksMap = noteWithTasks.taskById;

            return AdaptiveScaffold(
              resizeToAvoidBottomInset: false,
              appBar: AdaptiveAppBar(
                title: inbox.title,
                actions: [
                  AdaptiveAppBarAction(
                    icon: Icons.check,
                    iosSymbol: 'checkmark',
                    onPressed: () =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                  ),
                ],
              ),
              body: NoteEditor(
                noteId: inbox.id,
                nodes: nodes,
                taskMetadata: tasksMap,
                delegate: NoteEditorDelegate(
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
                        onComplete: () => ref
                            .read(tasksRepositoryProvider)
                            .completeTask(taskId),
                        onUndo: (previousDue) => ref
                            .read(tasksRepositoryProvider)
                            .reopenTask(taskId, originalDueDate: previousDue),
                      ),
                  onTaskReopen: (taskId) => ref
                      .read(tasksRepositoryProvider)
                      .reopenTask(taskId),
                ),
              ),
              floatingActionButton: _hasContent ? _buildOrganizeFab : null,
            );
          },
          loading: () =>
              _fallbackScaffold(const CircularProgressIndicator()),
          error: (error, _) =>
              _fallbackScaffold(Text('Error: $error')),
        );
      },
      loading: () =>
          _fallbackScaffold(const CircularProgressIndicator()),
      error: (error, _) => _fallbackScaffold(Text('Error: $error')),
    );
  }

  Widget? get _buildOrganizeFab {
    return FloatingActionButton(
      onPressed: _onOrganizePressed,
      child: const Icon(Icons.auto_awesome),
    );
  }
}

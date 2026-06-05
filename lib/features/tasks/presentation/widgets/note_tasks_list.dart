import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';

import '../../data/tasks_repository.dart';
import '../../domain/task_model.dart';
import 'task_edit_sheet.dart';
import 'task_tile.dart';

/// Embeddable list of the tasks belonging to a single note.
///
/// Renders a `ReorderableListView` of [TaskTile]s backed by
/// `tasksRepositoryProvider.watchByNote(noteId)`. The user can drag to
/// reorder (which calls `reorderTasks` to persist the new order), tap a
/// tile to edit it, and tap the trailing "+ Adicionar tarefa" row to
/// open the [TaskEditSheet] in create mode with the note id pre-filled.
///
/// Designed to be dropped into the note editor (Agent C may or may not
/// use it — integration is optional).
class NoteTasksList extends ConsumerWidget {
  const NoteTasksList({super.key, required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(tasksByNoteStreamProvider(noteId));

    return tasksAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text('Erro ao carregar tarefas: $e'),
      ),
      data: (tasks) => _NoteTasksListBody(noteId: noteId, tasks: tasks),
    );
  }
}

class _NoteTasksListBody extends ConsumerWidget {
  const _NoteTasksListBody({required this.noteId, required this.tasks});

  final String noteId;
  final List<TaskModel> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tasks.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _AddTaskRow(),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: true,
          itemCount: tasks.length,
          onReorder: (oldIndex, newIndex) {
            final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
            final mutable = [...tasks];
            final moved = mutable.removeAt(oldIndex);
            mutable.insert(adjusted, moved);
            ref
                .read(tasksRepositoryProvider)
                .reorderTasks(noteId, mutable.map((t) => t.id).toList());
          },
          itemBuilder: (context, index) {
            final task = tasks[index];
            return Padding(
              key: ValueKey('note-task-${task.id}'),
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: TaskTile(
                task: task,
                dense: true,
                onTap: () => _openEdit(context, ref, task),
                onToggleComplete: (v) => _toggleComplete(ref, task, v),
                onDelete: () =>
                    ref.read(tasksRepositoryProvider).deleteTask(task.id),
              ),
            );
          },
        ),
        const _AddTaskRow(),
      ],
    );
  }

  Future<void> _openEdit(
    BuildContext context,
    WidgetRef ref,
    TaskModel task,
  ) async {
    await TaskEditSheet.show(context, noteId: noteId, task: task);
  }

  void _toggleComplete(WidgetRef ref, TaskModel task, bool value) {
    final repo = ref.read(tasksRepositoryProvider);
    if (value && !task.isCompleted) {
      repo.completeTask(task.id);
    } else if (!value && task.isCompleted) {
      repo.reopenTask(task.id);
    }
  }
}

class _AddTaskRow extends StatelessWidget {
  const _AddTaskRow();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Builder(
      builder: (innerContext) {
        return ListTile(
          leading: Icon(Icons.add, color: scheme.primary),
          title: Text(
            'Adicionar tarefa',
            style: TextStyle(
              color: scheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
          onTap: () => _onTap(innerContext),
        );
      },
    );
  }

  Future<void> _onTap(BuildContext context) async {
    final noteTasksList =
        context.findAncestorWidgetOfExactType<NoteTasksList>();
    if (noteTasksList == null) return;
    await TaskEditSheet.show(context, noteId: noteTasksList.noteId);
  }
}

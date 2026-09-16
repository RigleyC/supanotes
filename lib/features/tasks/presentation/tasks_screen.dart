import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/tasks/application/task_controller.dart';
import 'package:supanotes/features/tasks/application/task_list_providers.dart';
import 'package:supanotes/features/tasks/domain/task_list_item.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_list_tile.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_button.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';
import 'package:supanotes/shared/widgets/app_tile.dart';
import 'package:supanotes/shared/widgets/empty_state.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  bool _includeNoteTasks = false;

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(
      taskListProvider(includeNoteTasks: _includeNoteTasks),
    );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.medium(title: Text('Tasks')),
          SliverPadding(
            padding: const EdgeInsets.all(AppSpacing.md),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                AppButton(
                  text: 'Nova task',
                  icon: const Icon(Icons.add_rounded),
                  onPressed: () => context.push(AppRoutes.standaloneTask),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppTile(
                  title: 'Mostrar tarefas das notas',
                  subtitle: 'Inclui tasks das notas visíveis nesta lista',
                  leading: const Icon(Icons.notes_outlined),
                  trailing: Switch(
                    key: const ValueKey('show-note-tasks-toggle'),
                    value: _includeNoteTasks,
                    onChanged: (value) =>
                        setState(() => _includeNoteTasks = value),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppTile(
                  title: 'Concluídas',
                  subtitle: 'Histórico de tasks concluídas',
                  leading: const Icon(Icons.task_alt_rounded),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(AppRoutes.completedTasks),
                ),
              ]),
            ),
          ),
          tasksAsync.when(
            loading: () => const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => SliverFillRemaining(
              hasScrollBody: false,
              child: AppErrorView(
                title: 'Erro ao carregar tasks',
                subtitle: error.toString(),
                onRetry: () => ref.invalidate(
                  taskListProvider(includeNoteTasks: _includeNoteTasks),
                ),
              ),
            ),
            data: (tasks) => _buildTaskSliver(context, tasks),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskSliver(BuildContext context, List<TaskListItem> tasks) {
    if (tasks.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          icon: Icons.check_circle_outline_rounded,
          title: 'Tudo em dia',
          subtitle: 'Adicione uma task para começar.',
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      sliver: SliverList.builder(
        itemCount: tasks.length,
        itemBuilder: (context, index) {
          final item = tasks[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: TaskListTile(
              item: item,
              onTap: () => _openTask(context, item),
              onToggle: item.isStandalone ? () => _completeTask(item) : null,
            ),
          );
        },
      ),
    );
  }

  void _openTask(BuildContext context, TaskListItem item) {
    if (item.isStandalone) {
      context.push('${AppRoutes.standaloneTask}/${item.task!.id}');
      return;
    }
    context.push(
      AppRoutes.note(item.note!.noteId, blockId: item.note!.blockId),
    );
  }

  Future<void> _completeTask(TaskListItem item) async {
    if (!item.isStandalone) return;
    try {
      await ref
          .read(taskControllerProvider)
          .complete(
            item.task!.id,
            scheduledAt: item.scheduledAt?.toIso8601String(),
          );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível concluir a task: $error')),
      );
    }
  }
}

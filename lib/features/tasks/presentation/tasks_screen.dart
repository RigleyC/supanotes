import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/tasks/application/task_controller.dart';
import 'package:supanotes/features/tasks/application/task_list_providers.dart';
import 'package:supanotes/features/tasks/domain/task_list_item.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_list_tile.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_source_filter_menu.dart';
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

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        useNativeToolbar: false,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            TaskSourceFilterMenu(
              key: const ValueKey('task-source-filter-menu'),
              includeNoteTasks: _includeNoteTasks,
              onChanged: (value) => setState(() => _includeNoteTasks = value),
            ),
          ],
        ),
        cupertinoNavigationBar: CupertinoNavigationBar(
          border: null,
          trailing: TaskSourceFilterMenu(
            key: const ValueKey('task-source-filter-menu'),
            includeNoteTasks: _includeNoteTasks,
            onChanged: (value) => setState(() => _includeNoteTasks = value),
          ),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                AppButton(
                  text: 'Nova task',
                  icon: const Icon(Icons.add_rounded),
                  onPressed: () => context.push(AppRoutes.standaloneTask),
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
            data: (tasks) {
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
                        onToggle: item.isStandalone
                            ? () => _completeTask(item)
                            : null,
                      ),
                    );
                  },
                ),
              );
            },
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.lg,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                AppTile(
                  key: const ValueKey('completed-tasks-entry'),
                  title: 'Concluídas',
                  subtitle: 'Histórico de tasks concluídas',
                  leading: const Icon(Icons.task_alt_rounded),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(AppRoutes.completedTasks),
                ),
              ]),
            ),
          ),
        ],
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

import 'dart:async';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/tasks/application/note_task_controller.dart';
import 'package:supanotes/features/tasks/application/task_controller.dart';
import 'package:supanotes/features/tasks/application/task_list_providers.dart';
import 'package:supanotes/features/tasks/domain/task_list_item.dart';
import 'package:supanotes/features/tasks/presentation/task_editor_screen.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_list_tile.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_source_filter_menu.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_button.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
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
    final bottomContentPadding =
        MediaQuery.paddingOf(context).bottom + AppSpacing.lg;
    final sourceFilterMenu = TaskSourceFilterMenu(
      key: const ValueKey('task-source-filter-menu'),
      includeNoteTasks: _includeNoteTasks,
      onChanged: (value) => setState(() => _includeNoteTasks = value),
    );

    return Scaffold(
      appBar: PlatformInfo.isIOS
          ? CupertinoNavigationBar(
              automaticallyImplyLeading: false,
              backgroundColor: CupertinoTheme.of(context).barBackgroundColor,
              border: null,
              trailing: sourceFilterMenu,
            )
          : AppBar(
              automaticallyImplyLeading: false,
              backgroundColor: Colors.transparent,
              elevation: 0,
              actions: [sourceFilterMenu],
            ),
      floatingActionButton: AppButton(
        variant: AppButtonVariant.fab,
        onPressed: () => unawaited(showTaskEditorSheet(context: context)),
        icon: const Icon(Icons.add_rounded),
      ),
      body: CustomScrollView(
        slivers: [
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
                        onTap: () => unawaited(_openTask(context, item)),
                        onToggle: () => unawaited(_completeTask(item)),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              bottomContentPadding,
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

  Future<void> _openTask(BuildContext context, TaskListItem item) async {
    if (item.isStandalone) {
      // Independent tasks use the standalone form in a modal from the list.
      // The route remains available for the primary action and deep links.
      await showTaskEditorSheet(
        context: context,
        taskId: item.task!.id,
      );
      return;
    }

    // Note tasks remain owned by the note document. Their full editor is the
    // note route, so this preserves the existing deep-link target instead of
    // accidentally routing the block through the standalone task repository.
    await context.push<void>(
      AppRoutes.note(item.note!.noteId, blockId: item.note!.blockId),
    );
  }

  Future<void> _completeTask(TaskListItem item) async {
    try {
      if (item.isStandalone) {
        await ref
            .read(taskControllerProvider)
            .complete(
              item.task!.id,
              scheduledAt: item.scheduledAt?.toIso8601String(),
            );
      } else {
        await ref
            .read(noteTaskControllerProvider)
            .complete(item.note!, scheduledAt: item.scheduledAt);
      }
    } on Object catch (error) {
      if (!mounted) return;
      AppMessenger.showError('Não foi possível concluir a task: $error');
    }
  }
}

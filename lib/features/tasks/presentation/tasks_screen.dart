import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/core/navigation/navigation_bar_insets.dart';
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
import 'package:supanotes/shared/widgets/empty_state.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  bool _includeNoteTasks = false;
  final Set<String> _dismissedTaskKeys = {};

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(
      taskListProvider(includeNoteTasks: _includeNoteTasks),
    );
    final sourceFilterMenu = TaskSourceFilterMenu(
      key: const ValueKey('task-source-filter-menu'),
      includeNoteTasks: _includeNoteTasks,
      onChanged: (value) => setState(() => _includeNoteTasks = value),
    );

    return Scaffold(
      appBar:
          defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS
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
      floatingActionButton: Padding(
        padding: NavigationBarInsets.scrollPadding(context),
        child: AppButton(
          heroTag: 'tasks-add-fab',
          variant: AppButtonVariant.fab,
          onPressed: () => unawaited(showTaskEditorSheet(context: context)),
          icon: const Icon(Icons.add_rounded),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
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
              final visibleTasks = tasks
                  .where((task) => !_dismissedTaskKeys.contains(task.uiKey))
                  .toList();
              final openTasks = visibleTasks
                  .where((task) => !task.isCompleted)
                  .toList();
              if (openTasks.isEmpty) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Center(
                          child: EmptyState(
                            icon: Icons.check_circle_outline_rounded,
                            title: 'Tudo em dia',
                            subtitle: 'Adicione uma task para come\u00e7ar.',
                          ),
                        ),
                      ),
                      _CompletedTasksEntry(),
                    ],
                  ),
                );
              }

              return SliverMainAxisGroup(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      0,
                      AppSpacing.md,
                      AppSpacing.md,
                    ),
                    sliver: SliverList.builder(
                      itemCount: openTasks.length,
                      itemBuilder: (context, index) {
                        final item = openTasks[index];
                        return Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppSpacing.sm,
                          ),
                          child: TaskListTile(
                            item: item,
                            checked: item.isCompleted,
                            completedAt: item.completedAt,
                            onTap: () => unawaited(_openTask(context, item)),
                            onToggle: () => _toggleTask(item),
                            onDelete: () => _deleteTask(item),
                          ),
                        );
                      },
                    ),
                  ),
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: _CompletedTasksEntry(),
                    ),
                  ),
                ],
              );
            },
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
        task: item.task,
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

  Future<void> _toggleTask(TaskListItem item) async {
    try {
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (item.isStandalone) {
        final controller = ref.read(taskControllerProvider);
        if (item.isCompleted) {
          await controller.reopen(
            item.task!.id,
            scheduledAt: item.scheduledAt?.toIso8601String(),
          );
        } else {
          await controller.complete(
            item.task!.id,
            scheduledAt: item.scheduledAt?.toIso8601String(),
          );
        }
      } else {
        final controller = ref.read(noteTaskControllerProvider);
        if (item.isCompleted) {
          await controller.reopen(item.note!, scheduledAt: item.scheduledAt);
        } else {
          await controller.complete(item.note!, scheduledAt: item.scheduledAt);
        }
      }
    } on Object catch (error) {
      if (mounted) {
        AppMessenger.showError('Não foi possível concluir a task: $error');
      }
      rethrow;
    }
  }

  Future<void> _deleteTask(TaskListItem item) async {
    setState(() => _dismissedTaskKeys.add(item.uiKey));
    try {
      if (item.isStandalone) {
        await ref.read(taskControllerProvider).delete(item.task!.id);
      } else {
        await ref.read(noteTaskControllerProvider).delete(item.note!);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _dismissedTaskKeys.remove(item.uiKey));
        AppMessenger.showError('Não foi possível excluir a task: $error');
      }
    }
  }
}

class _CompletedTasksEntry extends StatelessWidget {
  const _CompletedTasksEntry();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: NavigationBarInsets.scrollPadding(
        context,
        base: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          80,
        ),
      ),
      child: AppButton(
        key: const ValueKey('completed-tasks-entry'),
        variant: AppButtonVariant.secondary,
        text: 'Concluídas',
        icon: const Icon(Icons.task_alt_rounded),
        onPressed: () => context.push(AppRoutes.completedTasks),
      ),
    );
  }
}

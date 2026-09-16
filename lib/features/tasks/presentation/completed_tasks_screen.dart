import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/tasks/application/task_list_providers.dart';
import 'package:supanotes/features/tasks/domain/task_history_entry.dart';
import 'package:supanotes/features/tasks/presentation/widgets/completed_tasks_tile.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_source_filter_menu.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';
import 'package:supanotes/shared/widgets/empty_state.dart';

class CompletedTasksScreen extends ConsumerStatefulWidget {
  const CompletedTasksScreen({super.key});

  @override
  ConsumerState<CompletedTasksScreen> createState() =>
      _CompletedTasksScreenState();
}

class _CompletedTasksScreenState extends ConsumerState<CompletedTasksScreen> {
  bool _includeNoteTasks = false;

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(
      completedTaskHistoryProvider(includeNoteTasks: _includeNoteTasks),
    );
    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        useNativeToolbar: false,
        appBar: AppBar(
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
          backgroundColor: CupertinoTheme.of(context).barBackgroundColor,
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
          historyAsync.when(
            loading: () => const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => SliverFillRemaining(
              hasScrollBody: false,
              child: AppErrorView(
                title: 'Erro ao carregar o histórico',
                subtitle: error.toString(),
                onRetry: () => ref.invalidate(
                  completedTaskHistoryProvider(
                    includeNoteTasks: _includeNoteTasks,
                  ),
                ),
              ),
            ),
            data: (entries) {
              if (entries.isEmpty) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.history_rounded,
                    title: 'Nenhuma conclusão ainda',
                    subtitle: 'Tasks concluídas aparecerão aqui.',
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
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: CompletedTasksTile(
                        entry: entry,
                        onTap: () => _openEntry(context, entry),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _openEntry(BuildContext context, TaskHistoryEntry entry) {
    if (entry.task.isStandalone) {
      context.push('${AppRoutes.standaloneTask}/${entry.task.task!.id}');
      return;
    }
    context.push(
      AppRoutes.note(
        entry.task.note!.noteId,
        blockId: entry.task.note!.blockId,
      ),
    );
  }
}

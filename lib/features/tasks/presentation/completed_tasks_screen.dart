import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/tasks/application/task_list_providers.dart';
import 'package:supanotes/features/tasks/domain/task_history_entry.dart';
import 'package:supanotes/features/tasks/presentation/widgets/completed_tasks_tile.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';
import 'package:supanotes/shared/widgets/app_tile.dart';
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
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.medium(title: Text('Concluídas')),
          SliverPadding(
            padding: const EdgeInsets.all(AppSpacing.md),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                AppTile(
                  title: 'Mostrar tarefas das notas',
                  subtitle: 'Inclui conclusões vindas das notas',
                  leading: const Icon(Icons.notes_outlined),
                  trailing: Switch(
                    key: const ValueKey('show-note-tasks-history-toggle'),
                    value: _includeNoteTasks,
                    onChanged: (value) =>
                        setState(() => _includeNoteTasks = value),
                  ),
                ),
              ]),
            ),
          ),
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

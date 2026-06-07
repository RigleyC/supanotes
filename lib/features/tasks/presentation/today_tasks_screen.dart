import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/shared/theme/app_colors.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';

import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/presentation/controllers/today_tasks_controller.dart';
import 'package:supanotes/shared/widgets/empty_state.dart';
import 'widgets/quick_task_fab.dart';
import 'widgets/task_edit_sheet.dart';
import 'widgets/task_tile.dart';

/// "Hoje" surface — overdue, today-due, and undated pending tasks
/// stacked in collapsible sections, plus a FAB to add a quick task.
class TodayTasksScreen extends ConsumerWidget {
  const TodayTasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(todayTasksControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hoje'),
      ),
      floatingActionButton: const QuickTaskFAB(),
      body: tasksAsync.when(
        data: (state) {
          final overdue = state.overdue;
          final today = state.today;
          final undated = state.undated;
          final allEmpty = overdue.isEmpty && today.isEmpty && undated.isEmpty;

          if (allEmpty) {
            return const EmptyState(
              icon: Icons.celebration_outlined,
              title: 'Nenhuma task para hoje',
              subtitle: 'Aproveite o dia.',
            );
          }

          return CustomScrollView(
            slivers: [
              if (overdue.isNotEmpty)
                TaskSectionSliver(
                  title: 'Atrasadas',
                  accent: AppColors.muted,
                  badgeColor: Theme.of(context).colorScheme.error,
                  count: overdue.length,
                  children: [
                    for (final t in overdue)
                      Padding(
                        padding:
                            const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _TileHost(task: t),
                      ),
                  ],
                ),
              if (today.isNotEmpty)
                TaskSectionSliver(
                  title: 'Hoje',
                  accent: AppColors.success,
                  count: today.length,
                  children: [
                    for (final t in today)
                      Padding(
                        padding:
                            const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _TileHost(task: t),
                      ),
                  ],
                ),
              if (undated.isNotEmpty)
                TaskSectionSliver(
                  title: 'Sem data',
                  count: undated.length,
                  collapsible: true,
                  children: [
                    for (final t in undated)
                      Padding(
                        padding:
                            const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _TileHost(task: t),
                      ),
                  ],
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Erro: $err')),
      ),
    );
  }
}

class _TileHost extends ConsumerWidget {
  const _TileHost({required this.task});
  final TaskModel task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(todayTasksControllerProvider.notifier);
    return TaskTile(
      task: task,
      onTap: () async {
        await TaskEditSheet.show(context, noteId: task.noteId, task: task);
      },
      onToggleComplete: (v) {
        if (v && !task.isCompleted) {
          controller.completeTask(task.id);
        } else if (!v && task.isCompleted) {
          controller.reopenTask(task.id);
        }
      },
      onDelete: () => controller.deleteTask(task.id),
    );
  }
}

class TaskSectionSliver extends StatefulWidget {
  const TaskSectionSliver({
    super.key,
    required this.title,
    required this.children,
    this.count = 0,
    this.badgeColor,
    this.accent,
    this.collapsible = false,
  });

  final String title;
  final List<Widget> children;
  final int count;
  final Color? badgeColor;
  final Color? accent;
  final bool collapsible;

  @override
  State<TaskSectionSliver> createState() => _TaskSectionSliverState();
}

class _TaskSectionSliverState extends State<TaskSectionSliver> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _expanded = !widget.collapsible;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = widget.accent ?? theme.colorScheme.onSurface;
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;
    final isCollapsible = widget.collapsible;

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      sliver: SliverList.list(
        children: [
          if (isCollapsible)
            InkWell(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    Icon(
                      _expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 20,
                      color: onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      widget.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: onSurfaceVariant.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${widget.count}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  if (widget.badgeColor != null) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: widget.badgeColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Text(
                    widget.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: onSurface.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${widget.count}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (!isCollapsible || _expanded)
            ...widget.children,
        ],
      ),
    );
  }
}

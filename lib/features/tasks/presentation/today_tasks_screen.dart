import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/shared/theme/app_colors.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';

import '../data/tasks_repository.dart';
import '../domain/task_model.dart';
import 'widgets/quick_task_fab.dart';
import 'widgets/task_edit_sheet.dart';
import 'widgets/task_tile.dart';

/// "Hoje" surface — overdue, today-due, and undated pending tasks
/// stacked in collapsible sections, plus a FAB to add a quick task.
class TodayTasksScreen extends ConsumerWidget {
  const TodayTasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overdueAsync = ref.watch(overdueTasksStreamProvider);
    final todayAsync = ref.watch(todayDueTasksStreamProvider);
    final undatedAsync = ref.watch(undatedOpenTasksStreamProvider);

    final overdue = overdueAsync.value ?? const <TaskModel>[];
    final today = todayAsync.value ?? const <TaskModel>[];
    final undated = undatedAsync.value ?? const <TaskModel>[];

    final hasAnyData = overdueAsync.hasValue ||
        todayAsync.hasValue ||
        undatedAsync.hasValue;
    final allEmpty = overdue.isEmpty && today.isEmpty && undated.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hoje'),
      ),
      floatingActionButton: const QuickTaskFAB(),
      body: hasAnyData && allEmpty
          ? const _EmptyState()
          : CustomScrollView(
              slivers: [
                if (overdue.isNotEmpty)
                  _SectionSliver(
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
                  _SectionSliver(
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
                  _UndatedSectionSliver(
                    count: undated.length,
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
            ),
    );
  }
}

class _TileHost extends ConsumerWidget {
  const _TileHost({required this.task});
  final TaskModel task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TaskTile(
      task: task,
      onTap: () async {
        await TaskEditSheet.show(context, noteId: task.noteId, task: task);
      },
      onToggleComplete: (v) {
        final repo = ref.read(tasksRepositoryProvider);
        if (v && !task.isCompleted) {
          repo.completeTask(task.id);
        } else if (!v && task.isCompleted) {
          repo.reopenTask(task.id);
        }
      },
      onDelete: () => ref.read(tasksRepositoryProvider).deleteTask(task.id),
    );
  }
}

class _SectionSliver extends StatelessWidget {
  const _SectionSliver({
    required this.title,
    required this.children,
    this.count = 0,
    this.badgeColor,
    this.accent,
  });

  final String title;
  final List<Widget> children;
  final int count;
  final Color? badgeColor;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      sliver: SliverList.list(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                if (badgeColor != null) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: badgeColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: accent ?? theme.colorScheme.onSurface,
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
                    color: (accent ?? theme.colorScheme.onSurface)
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: accent ?? theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _UndatedSectionSliver extends StatefulWidget {
  const _UndatedSectionSliver({required this.children, required this.count});
  final List<Widget> children;
  final int count;

  @override
  State<_UndatedSectionSliver> createState() => _UndatedSectionSliverState();
}

class _UndatedSectionSliverState extends State<_UndatedSectionSliver> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      sliver: SliverList.list(
        children: [
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
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Sem data',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${widget.count}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: _expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: widget.children,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.celebration_outlined,
              size: 72,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Nenhuma task para hoje 🎉',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Aproveite o dia.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

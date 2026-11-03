import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/tasks/application/note_task_controller.dart';
import 'package:supanotes/features/tasks/application/task_controller.dart';
import 'package:supanotes/features/tasks/application/task_list_providers.dart';
import 'package:supanotes/features/tasks/domain/task_list_item.dart';
import 'package:supanotes/features/tasks/domain/task_schedule_identity.dart';
import 'package:supanotes/features/tasks/presentation/task_editor_screen.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_list_tile.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_source_filter_menu.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';
import 'package:supanotes/shared/widgets/app_navigation_bar.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  bool _includeNoteTasks = true;
  final Set<String> _dismissedTaskKeys = {};

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(
      taskListProvider(includeNoteTasks: _includeNoteTasks),
    );

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          TaskSourceFilterMenu(
            key: const ValueKey('task-source-filter-menu'),
            includeNoteTasks: _includeNoteTasks,
            onChanged: (value) => setState(() => _includeNoteTasks = value),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AppErrorView(
          title: 'Erro ao carregar tasks',
          subtitle: error.toString(),
          onRetry: () => ref.invalidate(
            taskListProvider(includeNoteTasks: _includeNoteTasks),
          ),
        ),
        data: (tasks) {
          final openTasks = tasks
              .where(
                (task) =>
                    !task.isCompleted &&
                    !_dismissedTaskKeys.contains(task.uiKey),
              )
              .toList();
          return _buildList(context, openTasks);
        },
      ),
    );
  }

  /// Lays the rows out top to bottom (sections, then the completed link) and
  /// renders them in a reverse list, so they sit just above the bottom bar
  /// when they fit and scroll lazily when they do not.
  Widget _buildList(BuildContext context, List<TaskListItem> openTasks) {
    final now = DateTime.now();
    final entries = <_Entry>[];
    if (openTasks.isEmpty) {
      entries.add(const _EmptyEntry());
    } else {
      final sections = <_TaskSection, List<TaskListItem>>{
        for (final section in _TaskSection.values) section: [],
      };
      for (final item in openTasks) {
        sections[_sectionOf(item, now)]!.add(item);
      }
      for (final MapEntry(key: section, value: items) in sections.entries) {
        if (items.isEmpty) continue;
        entries.add(_HeaderEntry(section));
        for (final item in items) {
          entries.add(_TaskEntry(item, section));
        }
      }
    }
    entries.add(const _CompletedLinkEntry());

    final overdueColor = Theme.of(context).colorScheme.error;
    final last = entries.length - 1;
    return ListView.builder(
      key: const ValueKey('tasks-list'),
      reverse: true,
      padding: EdgeInsets.only(
        top: 8,
        bottom: AppNavigationBar.contentBottomPadding(context),
      ),
      itemCount: entries.length,
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        final index = entries.indexWhere(
          (entry) => entry is _TaskEntry && entry.item.uiKey == key.value,
        );
        return index < 0 ? null : last - index;
      },
      itemBuilder: (context, index) {
        final entry = entries[last - index];
        switch (entry) {
          case _HeaderEntry(:final section):
            return _SectionHeader(section: section);
          case _TaskEntry(:final item, :final section):
            return KeyedSubtree(
              key: ValueKey(item.uiKey),
              child: Padding(
                padding: const EdgeInsets.only(
                  left: AppNavigationBar.contentInset - 14,
                  right: AppNavigationBar.contentInset,
                ),
                child: TaskListTile(
                  item: item,
                  checked: item.isCompleted,
                  trailingLabel: _scheduleLabel(item, now),
                  trailingColor: section == _TaskSection.overdue
                      ? overdueColor
                      : null,
                  onTap: () => unawaited(_openTask(context, item)),
                  onToggle: () => _toggleTask(item),
                  onDelete: () => _deleteTask(item),
                ),
              ),
            );
          case _EmptyEntry():
            return const _TasksEmptyMessage();
          case _CompletedLinkEntry():
            return const _CompletedTasksLink();
        }
      },
    );
  }

  Future<void> _openTask(BuildContext context, TaskListItem item) async {
    if (item.isStandalone) {
      // Independent tasks use the standalone form in a modal from the list.
      // The route remains available for the primary action and deep links.
      // The root navigator keeps the sheet above the shell's bottom bar.
      await showTaskEditorSheet(
        context: Navigator.of(context, rootNavigator: true).context,
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

enum _TaskSection {
  overdue('Atrasada'),
  today('Hoje'),
  later('Depois');

  const _TaskSection(this.label);

  final String label;
}

/// Mirrors the task list ordering groups: a dated task is overdue once its
/// canonical schedule is before now, so a timed task from earlier today is
/// overdue; tomorrow onwards and undated tasks are "later".
_TaskSection _sectionOf(TaskListItem item, DateTime now) {
  final due = item.dueDate;
  if (due == null) return _TaskSection.later;
  final hasTime = item.hasTime;
  if (canonicalScheduledAt(
    due,
    hasTime: hasTime,
  ).isBefore(canonicalScheduledAt(now, hasTime: hasTime))) {
    return _TaskSection.overdue;
  }
  if (_dayOffset(due, now) == 0) return _TaskSection.today;
  return _TaskSection.later;
}

/// Calendar days from [now] to [date], immune to DST-length days.
int _dayOffset(DateTime date, DateTime now) {
  final day = DateTime.utc(date.year, date.month, date.day);
  final today = DateTime.utc(now.year, now.month, now.day);
  return day.difference(today).inDays;
}

final _timeFormat = DateFormat('HH:mm');
DateFormat? _weekdayFormat;
DateFormat? _dayMonthFormat;

/// Short schedule at the end of a row: the time for a timed task today, else
/// a short day ("ontem", "amanhã", "sáb", "4 nov"). Undated tasks have none.
String? _scheduleLabel(TaskListItem item, DateTime now) {
  final due = item.dueDate;
  if (due == null) return null;
  final offset = _dayOffset(due, now);
  if (offset == 0) return item.hasTime ? _timeFormat.format(due) : null;
  if (offset == 1) return 'amanhã';
  if (offset == -1) return 'ontem';
  if (offset.abs() < 7) {
    return _stripDots(
      (_weekdayFormat ??= _localizedFormat('EEE')).format(due),
    );
  }
  final dayMonth = _stripDots(
    (_dayMonthFormat ??= _localizedFormat('d MMM')).format(due),
  );
  return due.year == now.year ? dayMonth : '$dayMonth ${due.year}';
}

DateFormat _localizedFormat(String pattern) {
  try {
    return DateFormat(pattern, 'pt_BR');
  } on Exception {
    // Locale data is initialized at startup; tests may skip it.
    return DateFormat(pattern);
  }
}

String _stripDots(String value) => value.replaceAll('.', '').toLowerCase();

sealed class _Entry {
  const _Entry();
}

final class _HeaderEntry extends _Entry {
  const _HeaderEntry(this.section);

  final _TaskSection section;
}

final class _TaskEntry extends _Entry {
  const _TaskEntry(this.item, this.section);

  final TaskListItem item;
  final _TaskSection section;
}

final class _EmptyEntry extends _Entry {
  const _EmptyEntry();
}

final class _CompletedLinkEntry extends _Entry {
  const _CompletedLinkEntry();
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.section});

  final _TaskSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppNavigationBar.contentInset,
        20,
        AppNavigationBar.contentInset,
        2,
      ),
      child: Semantics(
        header: true,
        child: Text(
          section.label,
          key: ValueKey('task-section-${section.name}'),
          style: (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
            fontSize: 13,
            height: 1.3,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
            color: section == _TaskSection.overdue
                ? scheme.error
                : scheme.onSurfaceVariant.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }
}

class _TasksEmptyMessage extends StatelessWidget {
  const _TasksEmptyMessage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyLarge?.copyWith(
      fontSize: 17,
      height: 1.4,
      letterSpacing: -0.1,
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
    );
    return Padding(
      key: const ValueKey('tasks-empty-state'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppNavigationBar.contentInset,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tudo em dia',
            style: style?.copyWith(fontWeight: FontWeight.w500),
          ),
          Text('Adicione uma task para começar.', style: style),
        ],
      ),
    );
  }
}

/// Discreet link to the completion history at the end of the list.
class _CompletedTasksLink extends StatelessWidget {
  const _CompletedTasksLink();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        link: true,
        child: GestureDetector(
          key: const ValueKey('completed-tasks-entry'),
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(context.push(AppRoutes.completedTasks)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppNavigationBar.contentInset,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Concluídas',
                  style: (theme.textTheme.bodyMedium ?? const TextStyle())
                      .copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.8,
                        ),
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

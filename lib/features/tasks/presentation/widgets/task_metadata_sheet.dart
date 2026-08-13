import 'dart:developer' as dev;

import 'package:family_bottom_sheet/family_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:supanotes/features/tasks/domain/task_date_format.dart';
import 'package:supanotes/features/tasks/domain/task_notification_scheduler.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_reminder_option.dart';
import 'package:supanotes/core/utils/app_haptics.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_icon_button.dart';
import 'package:supanotes/shared/widgets/global_sheet.dart';

import '../controllers/task_metadata_controller.dart';
import '../controllers/task_metadata_draft.dart';
import 'task_metadata_date_page.dart';
import 'task_metadata_selection_page.dart';
import 'task_metadata_time_page.dart';

Future<void> showTaskMetadataSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String taskId,
  required TaskMetadataDraft draft,
  required Future<void> Function(TaskMetadataDraft draft) onSave,
}) async {
  final controller = ref.read(taskMetadataProvider(taskId).notifier)
    ..initialize(draft);

  try {
    await showGlobalSheet<void>(
      context: context,
      builder: (ctx) => GlobalSheetPage(
        title: 'Editar horário e frequência',
        child: TaskMetadataSheetBody(taskId: taskId),
      ),
    );

    final state = ref.read(taskMetadataProvider(taskId));
    dev.log(
      '[TaskMetadataSheet] Persisting on close: taskId=$taskId dueDate=${state.dueDate} hasTime=${state.hasTime} recurrence=${state.recurrence?.name} reminder=${state.reminder?.value}',
      name: 'TaskMetadataSheet',
    );
    await onSave(
      TaskMetadataDraft(
        scheduleAnchor: state.dueDate,
        hasTime: state.hasTime,
        recurrence: state.recurrence,
        reminder: state.reminder,
      ),
    );

    if (state.reminder != null) {
      try {
        final scheduler = ref.read(taskNotificationSchedulerProvider.notifier);
        await scheduler.requestPermissionForReminder();
      } catch (error, stackTrace) {
        dev.log(
          '[TaskMetadataSheet] Notification permission failed',
          name: 'TaskMetadataSheet',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  } finally {
    controller.releaseSheet();
    ref.invalidate(taskMetadataProvider(taskId));
  }
}

class TaskMetadataSheetBody extends ConsumerWidget {
  const TaskMetadataSheetBody({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(taskMetadataProvider(taskId));
    final controller = ref.read(taskMetadataProvider(taskId).notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DateTile(
            dueDate: state.dueDate,
            hasTime: state.hasTime,
            onTap: () {
              AppHaptics.controlTap();
              FamilyModalSheet.of(context).pushPage(
                TaskMetadataDatePage(
                  selected: state.dueDate,
                  onSelected: (date) {
                    controller.setDueDate(date);
                  },
                ),
              );
            },
            onClear: controller.clearDueDate,
          ),
          _TimeTile(
            dueDate: state.dueDate,
            hasTime: state.hasTime,
            onTap: () {
              AppHaptics.controlTap();
              FamilyModalSheet.of(context).pushPage(
                TaskMetadataTimePage(
                  currentDueDate: state.dueDate ?? DateTime.now(),
                  hasTime: state.hasTime,
                  onSelected: (date, {required bool hasTime}) {
                    controller.setTime(date, hasTime: hasTime);
                  },
                ),
              );
            },
            onClear: controller.clearTime,
          ),
          _RecurrenceTile(
            recurrence: state.recurrence,
            dueDate: state.dueDate,
            onTap: () {
              AppHaptics.controlTap();
              FamilyModalSheet.of(context).pushPage(
                TaskMetadataSelectionPage<TaskRecurrence>(
                  title: 'Repetição',
                  selected: state.recurrence,
                  options: TaskRecurrence.values,
                  noneLabel: 'Nenhuma',
                  optionLabel: (recurrence) =>
                      recurrence.getLocalizedLabel(state.dueDate),
                  optionIcon: (recurrence) => recurrence.icon,
                  onSelected: (r) {
                    controller.setRecurrence(r);
                  },
                ),
              );
            },
            onClear: () => controller.setRecurrence(null),
          ),
          _ReminderTile(
            reminder: state.reminder,
            onTap: () {
              AppHaptics.controlTap();
              FamilyModalSheet.of(context).pushPage(
                TaskMetadataSelectionPage<TaskReminderOption>(
                  title: 'Lembrete',
                  selected: state.reminder,
                  options: TaskReminderOption.values.where(
                    (option) => option.isRelative == state.hasTime,
                  ),
                  noneLabel: 'Nenhum',
                  optionLabel: (reminder) => reminder.label,
                  optionIcon: (_) => Icons.notifications_outlined,
                  onSelected: (reminder) {
                    controller.setReminder(reminder);
                  },
                ),
              );
            },
            onClear: () => controller.setReminder(null),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.dueDate,
    required this.hasTime,
    required this.onTap,
    required this.onClear,
  });

  final DateTime? dueDate;
  final bool hasTime;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasDueDate = dueDate != null;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        Icons.calendar_today_rounded,
        size: 20,
        color: hasDueDate ? scheme.primary : scheme.onSurface,
      ),
      title: Text(
        hasDueDate
            ? formatDueDate(dueDate!, hasTime: hasTime)
            : 'Adicionar data',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: hasDueDate ? scheme.primary : scheme.onSurface,
          fontWeight: hasDueDate ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      trailing: hasDueDate
          ? AppIconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              tooltip: 'Remover data',
              onPressed: onClear,
            )
          : null,
      onTap: onTap,
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.dueDate,
    required this.hasTime,
    required this.onTap,
    required this.onClear,
  });

  final DateTime? dueDate;
  final bool hasTime;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasValue = hasTime && dueDate != null;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        Icons.access_time_rounded,
        color: hasValue ? scheme.primary : scheme.onSurfaceVariant,
        size: 20,
      ),
      title: Text(
        hasValue ? DateFormat('h:mm a').format(dueDate!) : 'Adicionar horário',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: hasValue ? scheme.primary : scheme.onSurface,
          fontWeight: hasValue ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      trailing: hasTime
          ? AppIconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              tooltip: 'Remover horário',
              onPressed: onClear,
            )
          : null,
      onTap: onTap,
    );
  }
}

class _RecurrenceTile extends StatelessWidget {
  const _RecurrenceTile({
    required this.recurrence,
    required this.dueDate,
    required this.onTap,
    required this.onClear,
  });

  final TaskRecurrence? recurrence;
  final DateTime? dueDate;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasValue = recurrence != null;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        Icons.refresh_rounded,
        size: 20,
        color: hasValue ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(
        hasValue
            ? recurrence!.getLocalizedLabel(dueDate)
            : 'Adicionar recorrência',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: hasValue ? scheme.primary : scheme.onSurface,
          fontWeight: hasValue ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      trailing: hasValue
          ? AppIconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              tooltip: 'Remover recorrência',
              onPressed: onClear,
            )
          : null,
      onTap: onTap,
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({
    required this.reminder,
    required this.onTap,
    required this.onClear,
  });

  final TaskReminderOption? reminder;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasValue = reminder != null;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        Icons.notifications_outlined,
        size: 20,
        color: hasValue ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(
        reminder?.label ?? 'Adicionar lembrete',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: hasValue ? scheme.primary : scheme.onSurface,
          fontWeight: hasValue ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      trailing: hasValue
          ? AppIconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              tooltip: 'Remover lembrete',
              onPressed: onClear,
            )
          : null,
      onTap: onTap,
    );
  }
}

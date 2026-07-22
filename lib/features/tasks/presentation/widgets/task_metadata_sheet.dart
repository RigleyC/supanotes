import 'dart:developer' as dev;

import 'package:family_bottom_sheet/family_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:supanotes/features/tasks/domain/task_date_format.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_notification_scheduler.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_reminder_option.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';

import '../controllers/task_metadata_controller.dart';
import 'task_metadata_date_page.dart';
import 'task_metadata_selection_page.dart';
import 'task_metadata_time_page.dart';

Future<void> showTaskMetadataSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String noteId,
  required TaskModel task,
  required Future<void> Function({
    required DateTime? dueDate,
    required bool hasTime,
    required TaskRecurrence? recurrence,
    required String? reminder,
  })
  onSave,
}) async {
  final taskId = task.id;

  ref.read(taskMetadataProvider(taskId).notifier).initialize(task);

  await FamilyModalSheet.show<void>(
    context: context,
    isDismissible: true,
    enableDrag: true,
    contentBackgroundColor: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF333333)
        : Theme.of(context).colorScheme.surface,
    builder: (ctx) => TaskMetadataSheetBody(noteId: noteId, taskId: taskId),
  );

  final state = ref.read(taskMetadataProvider(taskId));

  dev.log(
    '[TaskMetadataSheet] Persisting: taskId=$taskId dueDate=${state.dueDate} hasTime=${state.hasTime} recurrence=${state.recurrence?.name} reminder=${state.reminder?.value}',
    name: 'TaskMetadataSheet',
  );

  await onSave(
    dueDate: state.dueDate,
    hasTime: state.hasTime,
    recurrence: state.recurrence,
    reminder: state.reminder?.value,
  );

  if (state.reminder != null) {
    final scheduler = ref.read(taskNotificationSchedulerProvider.notifier);
    await scheduler.requestPermissionForReminder();
  }

  ref.invalidate(taskMetadataProvider(taskId));
}

class TaskMetadataSheetBody extends ConsumerWidget {
  const TaskMetadataSheetBody({
    super.key,
    required this.noteId,
    required this.taskId,
  });

  final String noteId;
  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(taskMetadataProvider(taskId));
    final controller = ref.read(taskMetadataProvider(taskId).notifier);

    return Material(
      type: MaterialType.transparency,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Editar horário e frequência',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            _DateTile(
              dueDate: state.dueDate,
              hasTime: state.hasTime,
              onTap: () => FamilyModalSheet.of(context).pushPage(
                TaskMetadataDatePage(
                  selected: state.dueDate,
                  onSelected: (date) {
                    controller.setDueDate(date);
                  },
                ),
              ),
              onClear: controller.clearDueDate,
            ),
            _TimeTile(
              dueDate: state.dueDate,
              hasTime: state.hasTime,
              onTap: () => FamilyModalSheet.of(context).pushPage(
                TaskMetadataTimePage(
                  currentDueDate: state.dueDate ?? DateTime.now(),
                  hasTime: state.hasTime,
                  onSelected: (date, {required bool hasTime}) {
                    controller.setTime(date, hasTime: hasTime);
                  },
                ),
              ),
              onClear: controller.clearTime,
            ),
            _RecurrenceTile(
              recurrence: state.recurrence,
              dueDate: state.dueDate,
              onTap: () => FamilyModalSheet.of(context).pushPage(
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
              ),
              onClear: () => controller.setRecurrence(null),
            ),
            _ReminderTile(
              reminder: state.reminder,
              onTap: () => FamilyModalSheet.of(context).pushPage(
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
              ),
              onClear: () => controller.setReminder(null),
            ),
          ],
        ),
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
          ? IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
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
          ? IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
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
          ? IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
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
          ? IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: onClear,
            )
          : null,
      onTap: onTap,
    );
  }
}

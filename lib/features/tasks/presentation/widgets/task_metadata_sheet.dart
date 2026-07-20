import 'dart:developer' as dev;

import 'package:family_bottom_sheet/family_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supanotes/core/utils/date_time_extensions.dart';

import 'package:supanotes/features/notes/presentation/controllers/note_editor_provider.dart';
import 'package:supanotes/features/tasks/domain/task_date_format.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_notification_scheduler.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_reminder_option.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';

import '../controllers/task_metadata_controller.dart';
import 'task_metadata_date_page.dart';
import 'task_metadata_recurrence_page.dart';
import 'task_metadata_reminder_page.dart';
import 'task_metadata_time_page.dart';

Future<void> showTaskMetadataSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String noteId,
  required TaskModel task,
}) async {
  final taskId = task.id;

  ref.read(taskMetadataProvider(taskId).notifier).state =
      taskMetadataStateFromModel(task);

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
    '[TaskMetadataSheet] Persisting: taskId=$taskId dueDate=${state.dueDate} hasTime=${state.hasTime} recurrence=${state.recurrence?.name} reminder=${state.reminder?.yjsValue}',
    name: 'TaskMetadata',
  );

  ref
      .read(noteEditorControllerProvider(noteId))
      .updateTaskMetadataInYDoc(
        taskId,
        dueDate: state.dueDate,
        clearDueDate: state.dueDate == null,
        recurrence: state.recurrence?.name,
        clearRecurrence: state.recurrence == null,
        hasTime: state.hasTime,
        reminder: state.reminder?.yjsValue,
        clearReminder: state.reminder == null,
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
    final notifier = ref.read(taskMetadataProvider(taskId).notifier);

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
                  final oldDueDate = state.dueDate;
                  final mergedDate = (oldDueDate != null && state.hasTime)
                      ? DateTime(date.year, date.month, date.day, oldDueDate.hour, oldDueDate.minute)
                      : date;
                  notifier.state = TaskMetadataState(
                    dueDate: mergedDate,
                    hasTime: state.hasTime,
                    recurrence: state.recurrence,
                    reminder: state.reminder,
                  );
                },
              ),
            ),
            onClear: () {
              notifier.state = TaskMetadataState();
            },
          ),
          _TimeTile(
            dueDate: state.dueDate,
            hasTime: state.hasTime,
            onTap: () => FamilyModalSheet.of(context).pushPage(
              TaskMetadataTimePage(
                currentDueDate: state.dueDate!,
                hasTime: state.hasTime,
                onSelected: (date, {required bool hasTime}) {
                  notifier.state = TaskMetadataState(
                    dueDate: date,
                    hasTime: hasTime,
                    recurrence: state.recurrence,
                    reminder: state.reminder,
                  );
                },
              ),
            ),
            onClear: () {
              notifier.state = TaskMetadataState(
                dueDate: state.dueDate,
                hasTime: false,
                recurrence: state.recurrence,
                reminder: state.reminder?.toAllDayFallback(),
              );
            },
          ),
          _RecurrenceTile(
            recurrence: state.recurrence,
            dueDate: state.dueDate,
            onTap: () => FamilyModalSheet.of(context).pushPage(
              TaskMetadataRecurrencePage(
                selected: state.recurrence,
                dueDate: state.dueDate,
                onSelected: (r) {
                  notifier.state = TaskMetadataState(
                    dueDate:
                        state.dueDate ??
                        (r != null ? DateTime.now().startOfDay : null),
                    hasTime: state.hasTime,
                    recurrence: r,
                    reminder: state.reminder,
                  );
                },
              ),
            ),
            onClear: () {
              notifier.state = TaskMetadataState(
                dueDate: state.dueDate,
                hasTime: state.hasTime,
                recurrence: null,
                reminder: state.reminder,
              );
            },
          ),
          _ReminderTile(
            reminder: state.reminder,
            onTap: () => FamilyModalSheet.of(context).pushPage(
              TaskMetadataReminderPage(
                selected: state.reminder,
                hasTime: state.hasTime,
                onSelected: (reminder) {
                  notifier.state = TaskMetadataState(
                    dueDate: state.dueDate,
                    hasTime: state.hasTime,
                    recurrence: state.recurrence,
                    reminder: reminder,
                  );
                },
              ),
            ),
            onClear: () {
              notifier.state = TaskMetadataState(
                dueDate: state.dueDate,
                hasTime: state.hasTime,
                recurrence: state.recurrence,
                reminder: null,
              );
            },
          ),
        ],
      ),
    ));
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(Icons.calendar_today_rounded, size: 20),
      title: Text(
        dueDate != null
            ? formatDueDate(dueDate!, hasTime: hasTime)
            : 'Adicionar data',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      trailing: dueDate != null
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
    final enabled = dueDate != null;
    final color = enabled
        ? null
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(Icons.access_time_rounded, color: color, size: 20),
      title: Text(
        hasTime && dueDate != null
            ? DateFormat('h:mm a').format(dueDate!)
            : 'Adicionar horário',
        style: color != null
            ? Theme.of(context).textTheme.titleSmall?.copyWith(color: color)
            : Theme.of(context).textTheme.titleSmall,
      ),
      trailing: hasTime
          ? IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: onClear,
            )
          : null,
      enabled: enabled,
      onTap: enabled ? onTap : null,
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(Icons.refresh_rounded, size: 20),
      title: Text(
        recurrence != null
            ? recurrence!.getLocalizedLabel(dueDate)
            : 'Adicionar recorrência',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      trailing: recurrence != null
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(Icons.notifications_outlined, size: 20),
      title: Text(
        reminder?.label ?? 'Adicionar lembrete',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      trailing: reminder != null
          ? IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: onClear,
            )
          : null,
      onTap: onTap,
    );
  }
}

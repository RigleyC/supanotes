import 'dart:developer' as dev;

import 'package:family_bottom_sheet/family_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:supanotes/core/utils/app_haptics.dart';
import 'package:supanotes/features/tasks/domain/task_date_format.dart';
import 'package:supanotes/features/tasks/domain/task_notification_scheduler.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_reminder_option.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_icon_button.dart';
import 'package:supanotes/shared/widgets/app_tile.dart';
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
    await onSave(TaskMetadataDraft(
      scheduleAnchor: state.dueDate,
      hasTime: state.hasTime,
      recurrence: state.recurrence,
      reminder: state.reminder,
    ));
    if (state.reminder != null) {
      try {
        await ref.read(taskNotificationSchedulerProvider.notifier)
            .requestPermissionForReminder();
      } catch (error, stackTrace) {
        dev.log('[TaskMetadataSheet] Notification permission failed',
            name: 'TaskMetadataSheet', error: error, stackTrace: stackTrace);
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
          AppTile(
            contentPadding: EdgeInsets.zero,
            title: state.dueDate == null ? 'Adicionar data' :
                formatDueDate(state.dueDate!, hasTime: state.hasTime),
            leading: const Icon(Icons.calendar_today_rounded, size: 20),
            trailing: state.dueDate == null ? null : AppIconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              tooltip: 'Remover data',
              onPressed: controller.clearDueDate,
            ),
            onTap: () {
              AppHaptics.controlTap();
              FamilyModalSheet.of(context).pushPage(TaskMetadataDatePage(
                selected: state.dueDate,
                onSelected: controller.setDueDate,
              ));
            },
          ),
          AppTile(
            contentPadding: EdgeInsets.zero,
            title: state.hasTime && state.dueDate != null
                ? DateFormat('h:mm a').format(state.dueDate!)
                : 'Adicionar horário',
            leading: const Icon(Icons.access_time_rounded, size: 20),
            trailing: state.hasTime ? AppIconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              tooltip: 'Remover horário',
              onPressed: controller.clearTime,
            ) : null,
            onTap: () {
              AppHaptics.controlTap();
              FamilyModalSheet.of(context).pushPage(TaskMetadataTimePage(
                currentDueDate: state.dueDate ?? DateTime.now(),
                hasTime: state.hasTime,
                onSelected: controller.setTime,
              ));
            },
          ),
          AppTile(
            contentPadding: EdgeInsets.zero,
            title: state.recurrence?.getLocalizedLabel(state.dueDate) ??
                'Adicionar recorrência',
            leading: const Icon(Icons.refresh_rounded, size: 20),
            trailing: state.recurrence == null ? null : AppIconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              tooltip: 'Remover recorrência',
              onPressed: () => controller.setRecurrence(null),
            ),
            onTap: () {
              AppHaptics.controlTap();
              FamilyModalSheet.of(context).pushPage(
                TaskMetadataSelectionPage<TaskRecurrence>(
                  title: 'Repetição', selected: state.recurrence,
                  options: TaskRecurrence.values, noneLabel: 'Nenhuma',
                  optionLabel: (value) => value.getLocalizedLabel(state.dueDate),
                  optionIcon: (value) => value.icon,
                  onSelected: controller.setRecurrence,
                ),
              );
            },
          ),
          AppTile(
            contentPadding: EdgeInsets.zero,
            title: state.reminder?.label ?? 'Adicionar lembrete',
            leading: const Icon(Icons.notifications_outlined, size: 20),
            trailing: state.reminder == null ? null : AppIconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              tooltip: 'Remover lembrete',
              onPressed: () => controller.setReminder(null),
            ),
            onTap: () {
              AppHaptics.controlTap();
              FamilyModalSheet.of(context).pushPage(
                TaskMetadataSelectionPage<TaskReminderOption>(
                  title: 'Lembrete', selected: state.reminder,
                  options: TaskReminderOption.values.where(
                    (option) => option.isRelative == state.hasTime,
                  ), noneLabel: 'Nenhum',
                  optionLabel: (value) => value.label,
                  optionIcon: (_) => Icons.notifications_outlined,
                  onSelected: controller.setReminder,
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

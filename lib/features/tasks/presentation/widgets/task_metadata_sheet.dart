import 'package:family_bottom_sheet/family_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:supanotes/features/notes/presentation/controllers/note_editor_provider.dart';
import 'package:supanotes/features/tasks/domain/task_date_format.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';

import 'task_metadata_controller.dart';
import 'task_metadata_date_page.dart';
import 'task_metadata_recurrence_page.dart';
import 'task_metadata_time_page.dart';

Future<void> showTaskMetadataSheet({
  required BuildContext context,
  required String noteId,
  required TaskModel task,
}) {
  return FamilyModalSheet.show<void>(
    context: context,
    isDismissible: true,
    enableDrag: true,
    contentBackgroundColor: const Color(0XFF333333),
    builder: (ctx) => ProviderScope(
      overrides: [
        taskMetadataTaskProvider.overrideWithValue(task),
      ],
      child: TaskMetadataSheetBody(noteId: noteId, taskId: task.id),
    ),
  );
}

class TaskMetadataSheetBody extends ConsumerStatefulWidget {
  const TaskMetadataSheetBody({
    super.key,
    required this.noteId,
    required this.taskId,
  });

  final String noteId;
  final String taskId;

  @override
  ConsumerState<TaskMetadataSheetBody> createState() =>
      _TaskMetadataSheetBodyState();
}

class _TaskMetadataSheetBodyState
    extends ConsumerState<TaskMetadataSheetBody> {
  @override
  void dispose() {
    final state = ref.read(taskMetadataControllerProvider);
    ref
        .read(noteEditorControllerProvider(widget.noteId))
        .updateTaskMetadataInYDoc(
          widget.taskId,
          dueDate: state.dueDate,
          clearDueDate: state.dueDate == null,
          recurrence: state.recurrence?.name,
          clearRecurrence: state.recurrence == null,
          hasTime: state.hasTime,
        );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.watch(taskMetadataControllerProvider);
    return Container(
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
            dueDate: ctrl.dueDate,
            hasTime: ctrl.hasTime,
            onTap: () => FamilyModalSheet.of(context).pushPage(
              TaskMetadataDatePage(
                selected: ctrl.dueDate,
                onSelected:
                    ref.read(taskMetadataControllerProvider.notifier).setDate,
              ),
            ),
            onClear:
                ref.read(taskMetadataControllerProvider.notifier).clearDate,
          ),
          _TimeTile(
            dueDate: ctrl.dueDate,
            hasTime: ctrl.hasTime,
            onTap: () => FamilyModalSheet.of(context).pushPage(
              TaskMetadataTimePage(
                currentDueDate: ctrl.dueDate!,
                onSelected:
                    ref.read(taskMetadataControllerProvider.notifier).setTime,
              ),
            ),
            onClear:
                ref.read(taskMetadataControllerProvider.notifier).clearTime,
          ),
          _RecurrenceTile(
            recurrence: ctrl.recurrence,
            dueDate: ctrl.dueDate,
            onTap: () => FamilyModalSheet.of(context).pushPage(
              TaskMetadataRecurrencePage(
                selected: ctrl.recurrence,
                dueDate: ctrl.dueDate,
                onSelected:
                    ref.read(taskMetadataControllerProvider.notifier).setRecurrence,
              ),
            ),
            onClear: ref
                .read(taskMetadataControllerProvider.notifier)
                .clearRecurrence,
          ),
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      tileColor: Colors.transparent,
      dense: true,
      leading: const Icon(Icons.calendar_today_rounded, size: 20),
      title: Text(
        dueDate != null
            ? formatDueDate(dueDate!, hasTime: hasTime)
            : 'Adicionar data',
        style: Theme.of(context).textTheme.bodyMedium,
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
      tileColor: Colors.transparent,
      dense: true,
      leading: Icon(Icons.access_time_rounded, color: color, size: 20),
      title: Text(
        hasTime && dueDate != null
            ? DateFormat('HH:mm').format(dueDate!)
            : 'Adicionar horário',
        style: color != null
            ? Theme.of(context).textTheme.bodyMedium?.copyWith(color: color)
            : Theme.of(context).textTheme.bodyMedium,
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
      tileColor: Colors.transparent,
      dense: true,
      leading: Icon(Icons.refresh_rounded, size: 20),
      title: Text(
        recurrence != null
            ? recurrence!.getLocalizedLabel(dueDate)
            : 'Adicionar recorrência',
        style: Theme.of(context).textTheme.bodyMedium,
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

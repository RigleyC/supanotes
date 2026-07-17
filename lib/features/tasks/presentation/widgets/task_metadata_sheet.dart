import 'package:family_bottom_sheet/family_bottom_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:supanotes/core/utils/date_time_extensions.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_provider.dart';
import 'package:supanotes/features/tasks/domain/task_date_format.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/shared/widgets/app_button.dart';
import 'package:supanotes/shared/widgets/app_selection_tile.dart';

import 'due_date_picker.dart' show QuickDueDate;

@immutable
class TaskMetadataState {
  final DateTime? dueDate;
  final bool hasTime;
  final TaskRecurrence? recurrence;

  const TaskMetadataState({this.dueDate, this.hasTime = false, this.recurrence});
}

final _taskModelProvider = Provider.autoDispose<TaskModel>((ref) {
  throw UnimplementedError('Override me');
});

class TaskMetadataController extends Notifier<TaskMetadataState> {
  @override
  TaskMetadataState build() {
    final task = ref.watch(_taskModelProvider);
    return TaskMetadataState(
      dueDate: task.dueDate,
      hasTime: task.hasTime,
      recurrence: task.recurrence,
    );
  }

  void setDate(DateTime date) {
    state = TaskMetadataState(dueDate: date);
  }

  void setTime(DateTime date, {required bool hasTime}) {
    state = TaskMetadataState(dueDate: date, hasTime: hasTime);
  }

  void setRecurrence(TaskRecurrence? r) {
    final dueDate = state.dueDate ??
        (r != null ? DateTime.now().startOfDay : null);
    state = TaskMetadataState(dueDate: dueDate, recurrence: r);
  }

  void clearDate() {
    state = const TaskMetadataState();
  }

  void clearTime() {
    state = TaskMetadataState(dueDate: state.dueDate);
  }

  void clearRecurrence() {
    state = TaskMetadataState(dueDate: state.dueDate, hasTime: state.hasTime);
  }
}

final taskMetadataControllerProvider =
    NotifierProvider<TaskMetadataController, TaskMetadataState>(
  TaskMetadataController.new,
);

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
        _taskModelProvider.overrideWithValue(task),
      ],
      child: _TaskMetadataSheetBody(noteId: noteId, taskId: task.id),
    ),
  );
}

class _TaskMetadataSheetBody extends ConsumerStatefulWidget {
  const _TaskMetadataSheetBody({
    required this.noteId,
    required this.taskId,
  });

  final String noteId;
  final String taskId;

  @override
  ConsumerState<_TaskMetadataSheetBody> createState() =>
      _TaskMetadataSheetBodyState();
}

class _TaskMetadataSheetBodyState
    extends ConsumerState<_TaskMetadataSheetBody> {
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
          const SizedBox(height: 16),
          _DateTile(
            dueDate: ctrl.dueDate,
            hasTime: ctrl.hasTime,
            onTap: () => FamilyModalSheet.of(context).pushPage(
              _TaskDatePage(
                selected: ctrl.dueDate,
                onSelected: ref.read(taskMetadataControllerProvider.notifier).setDate,
              ),
            ),
            onClear: ref.read(taskMetadataControllerProvider.notifier).clearDate,
          ),
          _TimeTile(
            dueDate: ctrl.dueDate,
            hasTime: ctrl.hasTime,
            onTap: () => FamilyModalSheet.of(context).pushPage(
              _TaskTimePage(
                currentDueDate: ctrl.dueDate!,
                onSelected: ref.read(taskMetadataControllerProvider.notifier).setTime,
              ),
            ),
            onClear: ref.read(taskMetadataControllerProvider.notifier).clearTime,
          ),
          _RecurrenceTile(
            recurrence: ctrl.recurrence,
            dueDate: ctrl.dueDate,
            onTap: () => FamilyModalSheet.of(context).pushPage(
              _TaskRecurrencePage(
                selected: ctrl.recurrence,
                dueDate: ctrl.dueDate,
                onSelected: ref.read(taskMetadataControllerProvider.notifier).setRecurrence,
              ),
            ),
            onClear:
                ref.read(taskMetadataControllerProvider.notifier).clearRecurrence,
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

class _TaskDatePage extends StatelessWidget {
  const _TaskDatePage({required this.selected, required this.onSelected});

  final DateTime? selected;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
          child: Text(
            'Escolher data',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          itemCount: QuickDueDate.values.length,
          itemBuilder: (context, index) {
            final option = QuickDueDate.values[index];
            final date = option.compute(now);
            return AppSelectionTile(
              label: option.label,
              icon: option.icon,
              isSelected: selected != null && selected!.isSameDayAs(date),
              onTap: () {
                onSelected(date);
                FamilyModalSheet.of(context).popPage();
              },
            );
          },
        ),
        const SizedBox(height: 12),
        CalendarDatePicker(
          initialDate: selected ?? now.startOfDay,
          firstDate: DateTime(now.year - 1),
          lastDate: DateTime(now.year + 5),
          onDateChanged: (date) {
            onSelected(date);
            FamilyModalSheet.of(context).popPage();
          },
        ),
      ],
    );
  }
}

class _TaskTimePage extends StatefulWidget {
  const _TaskTimePage({required this.currentDueDate, required this.onSelected});

  final DateTime currentDueDate;
  final void Function(DateTime date, {required bool hasTime}) onSelected;

  @override
  State<_TaskTimePage> createState() => _TaskTimePageState();
}

class _TaskTimePageState extends State<_TaskTimePage> {
  late Duration _duration;

  @override
  void initState() {
    super.initState();
    _duration = Duration(
      hours: widget.currentDueDate.hour,
      minutes: widget.currentDueDate.minute,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
          child: Text(
            'Escolher horário',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        SizedBox(
          height: 200,
          child: CupertinoTimerPicker(
            mode: CupertinoTimerPickerMode.hm,
            initialTimerDuration: _duration,
            onTimerDurationChanged: (d) => setState(() => _duration = d),
          ),
        ),
        const SizedBox(height: 16),
        AppButton(
          text: 'Confirmar',
          onPressed: () {
            final d = widget.currentDueDate;
            final newDate = DateTime(
              d.year,
              d.month,
              d.day,
              _duration.inHours,
              _duration.inMinutes.remainder(60),
            );
            widget.onSelected(newDate, hasTime: true);
            FamilyModalSheet.of(context).popPage();
          },
        ),
      ],
    );
  }
}

class _TaskRecurrencePage extends StatelessWidget {
  const _TaskRecurrencePage({
    required this.selected,
    required this.dueDate,
    required this.onSelected,
  });

  final TaskRecurrence? selected;
  final DateTime? dueDate;
  final ValueChanged<TaskRecurrence?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Repetição',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        AppSelectionTile(
          label: 'Nenhuma',
          icon: Icons.do_not_disturb_on_outlined,
          isSelected: selected == null,
          onTap: () {
            onSelected(null);
            FamilyModalSheet.of(context).popPage();
          },
        ),
        for (final option in TaskRecurrence.values)
          AppSelectionTile(
            label: option.getLocalizedLabel(dueDate),
            icon: option.icon,
            isSelected: option == selected,
            onTap: () {
              onSelected(option);
              FamilyModalSheet.of(context).popPage();
            },
          ),
      ],
    );
  }
}

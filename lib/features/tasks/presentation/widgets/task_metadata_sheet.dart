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

Future<void> showTaskMetadataSheet({
  required BuildContext context,
  required String noteId,
  required TaskModel task,
}) {
  return FamilyModalSheet.show<void>(
    context: context,
    isDismissible: true,
    enableDrag: true,
    contentBackgroundColor: Color(0XFF333333),
    builder: (ctx) => TaskMetadataSheet(noteId: noteId, task: task),
  );
}

class TaskMetadataSheet extends ConsumerStatefulWidget {
  const TaskMetadataSheet({
    super.key,
    required this.noteId,
    required this.task,
  });

  final String noteId;
  final TaskModel task;

  @override
  ConsumerState<TaskMetadataSheet> createState() => _TaskMetadataSheetState();
}

class _TaskMetadataSheetState extends ConsumerState<TaskMetadataSheet> {
  late DateTime? _dueDate;
  late TaskRecurrence? _recurrence;
  late bool _hasTime;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _dueDate = t.dueDate;
    _recurrence = t.recurrence;
    _hasTime = t.hasTime;
  }

  void _onClose() {
    ref
        .read(noteEditorControllerProvider(widget.noteId))
        .updateTaskMetadataInYDoc(
          widget.task.id,
          dueDate: _dueDate,
          clearDueDate: _dueDate == null,
          recurrence: _recurrence?.name,
          clearRecurrence: _recurrence == null,
          hasTime: _hasTime,
        );
  }

  @override
  void dispose() {
    _onClose();
    super.dispose();
  }

  void _onClearDate() {
    setState(() {
      _dueDate = null;
      _hasTime = false;
      _recurrence = null;
    });
  }

  void _onClearTime() {
    setState(() => _hasTime = false);
  }

  void _onClearRecurrence() {
    setState(() => _recurrence = null);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        cro
        children: [
          Text(
            'Editar horário e frequência',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          _DateTile(
            dueDate: _dueDate,
            hasTime: _hasTime,
            onTap: () => FamilyModalSheet.of(context).pushPage(
              _TaskDatePage(
                selected: _dueDate,
                onSelected: (date) => setState(() {
                  _dueDate = date;
                  _hasTime = false;
                }),
              ),
            ),
            onClear: _onClearDate,
          ),
          _TimeTile(
            dueDate: _dueDate,
            hasTime: _hasTime,
            onTap: () => FamilyModalSheet.of(context).pushPage(
              _TaskTimePage(
                currentDueDate: _dueDate!,
                onSelected: (date, {hasTime = false}) => setState(() {
                  _dueDate = date;
                  _hasTime = hasTime;
                }),
              ),
            ),
            onClear: _onClearTime,
          ),
          _RecurrenceTile(
            recurrence: _recurrence,
            dueDate: _dueDate,
            onTap: () => FamilyModalSheet.of(context).pushPage(
              _TaskRecurrencePage(
                selected: _recurrence,
                dueDate: _dueDate,
                onSelected: (r) => setState(() {
                  _recurrence = r;
                  if (r != null && _dueDate == null) {
                    _dueDate = DateTime.now().startOfDay;
                  }
                }),
              ),
            ),
            onClear: _onClearRecurrence,
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
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Escolher data',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        ...QuickDueDate.values.map((option) {
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
        }),
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
  final void Function(DateTime date, {bool hasTime}) onSelected;

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
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
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

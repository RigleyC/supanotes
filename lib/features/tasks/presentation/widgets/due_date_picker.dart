import 'package:flutter/material.dart';
import 'package:supanotes/core/utils/date_time_extensions.dart';
import 'package:supanotes/features/tasks/domain/task_date_format.dart';
import 'package:supanotes/shared/widgets/app_selection_tile.dart';
import 'package:supanotes/shared/widgets/app_time_picker.dart';

enum QuickDueDate {
  today,
  tomorrow,
  nextWeek;

  String get label {
    switch (this) {
      case QuickDueDate.today:
        return 'Hoje';
      case QuickDueDate.tomorrow:
        return 'Amanhã';
      case QuickDueDate.nextWeek:
        return 'Próxima semana';
    }
  }

  IconData get icon => Icons.calendar_month_rounded;

  DateTime compute(DateTime now) {
    final today = now.startOfDay;
    switch (this) {
      case QuickDueDate.today:
        return today;
      case QuickDueDate.tomorrow:
        return today.add(const Duration(days: 1));
      case QuickDueDate.nextWeek:
        return today.add(const Duration(days: 7));
    }
  }
}

class DueDatePicker extends StatefulWidget {
  const DueDatePicker({
    super.key,
    required this.initialDate,
    required this.onChanged,
    this.initialHasTime = false,
  });

  final DateTime? initialDate;
  final void Function(DateTime? date, {bool hasTime}) onChanged;
  final bool initialHasTime;

  @override
  State<DueDatePicker> createState() => _DueDatePickerState();
}

class _DueDatePickerState extends State<DueDatePicker> {
  bool _isCalendarExpanded = false;

  bool _isSelected(DateTime value) {
    if (widget.initialDate == null) return false;
    return value.isSameDayAs(widget.initialDate!);
  }

  bool _isCustomDate() {
    if (widget.initialDate == null) return false;
    return !widget.initialDate!.isQuickPick();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in QuickDueDate.values)
          AppSelectionTile(
            label: _isSelected(option.compute(now))
                ? formatDueDate(widget.initialDate!, hasTime: widget.initialHasTime, now: now)
                : option.label,
            icon: option.icon,
            isSelected: _isSelected(option.compute(now)),
            onTap: () {
              setState(() => _isCalendarExpanded = false);
              widget.onChanged(option.compute(now), hasTime: false);
            },
          ),
        AppSelectionTile(
          label: _isCustomDate()
              ? formatDueDate(
                  widget.initialDate!,
                  hasTime: widget.initialHasTime,
                  now: now,
                )
              : 'Escolher data',
          icon: Icons.calendar_month_rounded,
          isSelected: _isCustomDate(),
          onTap: () {
            setState(() => _isCalendarExpanded = !_isCalendarExpanded);
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _isCalendarExpanded
              ? ClipRect(
                  child: CalendarDatePicker(
                    initialDate: widget.initialDate ?? now.startOfDay,
                    firstDate: DateTime(now.year - 1),
                    lastDate: DateTime(now.year + 5),
                    onDateChanged: (date) {
                      setState(() => _isCalendarExpanded = false);
                      widget.onChanged(date, hasTime: false);
                    },
                  ),
                )
              : const SizedBox.shrink(),
        ),
        if (widget.initialDate != null)
          AppSelectionTile(
            label: 'Adicionar hora',
            icon: Icons.access_time_rounded,
            isSelected: widget.initialHasTime,
            onTap: () async {
              final time = await showAppTimePicker(
                context: context,
                initialTime: widget.initialHasTime && widget.initialDate != null
                    ? TimeOfDay.fromDateTime(widget.initialDate!)
                    : null,
              );
              if (time != null) {
                final date = widget.initialDate!;
                final newDate = DateTime(
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                );
                setState(() => _isCalendarExpanded = false);
                widget.onChanged(newDate, hasTime: true);
              }
            },
          ),
        AppSelectionTile(
          label: 'Sem data',
          icon: Icons.block,
          isSelected: widget.initialDate == null,
          onTap: () {
            setState(() => _isCalendarExpanded = false);
            widget.onChanged(null, hasTime: false);
          },
        ),
      ],
    );
  }
}

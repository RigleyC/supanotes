import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supanotes/core/utils/date_time_extensions.dart';
import 'package:supanotes/shared/widgets/app_selection_tile.dart';

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
    final today = now.startOfDay;
    final tomorrow = today.add(const Duration(days: 1));
    final nextWeek = today.add(const Duration(days: 7));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSelectionTile(
          label: 'Hoje',
          icon: Icons.calendar_month_rounded,
          isSelected: _isSelected(today),
          onTap: () {
            setState(() => _isCalendarExpanded = false);
            widget.onChanged(today, hasTime: false);
          },
        ),
        AppSelectionTile(
          label: 'Amanhã',
          icon: Icons.calendar_month_rounded,
          isSelected: _isSelected(tomorrow),
          onTap: () {
            setState(() => _isCalendarExpanded = false);
            widget.onChanged(tomorrow, hasTime: false);
          },
        ),
        AppSelectionTile(
          label: 'Próxima semana',
          icon: Icons.calendar_month_rounded,
          isSelected: _isSelected(nextWeek),
          onTap: () {
            setState(() => _isCalendarExpanded = false);
            widget.onChanged(nextWeek, hasTime: false);
          },
        ),
        AppSelectionTile(
          label: _isCustomDate()
              ? DateFormat('d MMM').format(widget.initialDate!)
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
                    initialDate: widget.initialDate ?? today,
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
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.now(),
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

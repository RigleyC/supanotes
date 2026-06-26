import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supanotes/core/utils/date_time_extensions.dart';
import 'package:supanotes/shared/widgets/app_selection_tile.dart';

class DueDatePicker extends StatefulWidget {
  const DueDatePicker({
    super.key,
    required this.initialDate,
    required this.onChanged,
  });

  final DateTime? initialDate;
  final ValueChanged<DateTime?> onChanged;

  @override
  State<DueDatePicker> createState() => _DueDatePickerState();
}

class _DueDatePickerState extends State<DueDatePicker> {
  bool _isCalendarExpanded = false;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = now.startOfDay;
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final nextMonday = today.add(Duration(days: 8 - today.weekday));

    bool isSelected(DateTime? value) {
      if (value == null || widget.initialDate == null) return false;
      return value.isSameDayAs(widget.initialDate!);
    }

    bool isCustomDate() {
      if (widget.initialDate == null) return false;
      return !_isQuickPick(widget.initialDate!, today, tomorrow, nextMonday);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSelectionTile(
          label: 'Hoje',
          icon: Icons.today_rounded,
          isSelected: isSelected(today),
          onTap: () {
            setState(() => _isCalendarExpanded = false);
            widget.onChanged(today);
          },
        ),
        AppSelectionTile(
          label: 'Amanhã',
          icon: Icons.wb_sunny_outlined,
          isSelected: isSelected(tomorrow),
          onTap: () {
            setState(() => _isCalendarExpanded = false);
            widget.onChanged(tomorrow);
          },
        ),
        AppSelectionTile(
          label: 'Próx. segunda',
          icon: Icons.date_range_rounded,
          isSelected: isSelected(nextMonday),
          onTap: () {
            setState(() => _isCalendarExpanded = false);
            widget.onChanged(nextMonday);
          },
        ),
        AppSelectionTile(
          label: isCustomDate()
              ? DateFormat('d MMM').format(widget.initialDate!)
              : 'Escolher data',
          icon: Icons.calendar_month_outlined,
          isSelected: isCustomDate(),
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
                      widget.onChanged(date);
                    },
                  ),
                )
              : const SizedBox.shrink(),
        ),
        AppSelectionTile(
          label: 'Sem data',
          icon: Icons.block,
          isSelected: widget.initialDate == null,
          onTap: () {
            setState(() => _isCalendarExpanded = false);
            widget.onChanged(null);
          },
        ),
      ],
    );
  }

  bool _isQuickPick(
    DateTime value,
    DateTime today,
    DateTime tomorrow,
    DateTime nextMonday,
  ) {
    return value.isSameDayAs(today) ||
        value.isSameDayAs(tomorrow) ||
        value.isSameDayAs(nextMonday);
  }
}

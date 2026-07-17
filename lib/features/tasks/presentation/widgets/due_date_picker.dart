import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supanotes/core/utils/date_time_extensions.dart';
import 'package:supanotes/shared/widgets/app_selection_tile.dart';

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
            label: option.label,
            icon: option.icon,
            isSelected: _isSelected(option.compute(now)),
            onTap: () {
              setState(() => _isCalendarExpanded = false);
              widget.onChanged(option.compute(now), hasTime: false);
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
              final time = defaultTargetPlatform == TargetPlatform.iOS
                  ? await _showCupertinoTimePicker(context)
                  : await _showMaterialTimePicker(context);
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

  Future<TimeOfDay?> _showMaterialTimePicker(BuildContext context) {
    return showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
  }

  Future<TimeOfDay?> _showCupertinoTimePicker(BuildContext context) async {
    final initial = TimeOfDay.now();
    return showCupertinoModalPopup<TimeOfDay>(
      context: context,
      builder: (_) {
        final hourController = FixedExtentScrollController(
          initialItem: initial.hour,
        );
        final minuteController = FixedExtentScrollController(
          initialItem: initial.minute,
        );
        return Container(
          height: 260,
          color: CupertinoColors.systemBackground,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    child: const Text('Cancelar'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  CupertinoButton(
                    child: const Text('OK'),
                    onPressed: () {
                      Navigator.of(context).pop(TimeOfDay(
                        hour: hourController.selectedItem,
                        minute: minuteController.selectedItem,
                      ));
                    },
                  ),
                ],
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: hourController,
                        itemExtent: 32,
                        onSelectedItemChanged: (_) {},
                        children: List.generate(24, (i) => Center(
                          child: Text(i.toString().padLeft(2, '0')),
                        )),
                      ),
                    ),
                    const Text(':'),
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: minuteController,
                        itemExtent: 32,
                        onSelectedItemChanged: (_) {},
                        children: List.generate(60, (i) => Center(
                          child: Text(i.toString().padLeft(2, '0')),
                        )),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

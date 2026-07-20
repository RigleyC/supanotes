import 'package:family_bottom_sheet/family_bottom_sheet.dart';
import 'package:flutter/cupertino.dart';

import 'package:supanotes/shared/widgets/app_button.dart';

import 'task_metadata_page_header.dart';

class TaskMetadataTimePage extends StatefulWidget {
  const TaskMetadataTimePage({
    super.key,
    required this.currentDueDate,
    required this.hasTime,
    required this.onSelected,
  });

  final DateTime currentDueDate;
  final bool hasTime;
  final void Function(DateTime date, {required bool hasTime}) onSelected;

  @override
  State<TaskMetadataTimePage> createState() => _TaskMetadataTimePageState();
}

class _TaskMetadataTimePageState extends State<TaskMetadataTimePage> {
  late DateTime _selectedTime;

  @override
  void initState() {
    super.initState();
    if (widget.hasTime) {
      _selectedTime = widget.currentDueDate;
    } else {
      final now = DateTime.now();
      _selectedTime = DateTime(
        widget.currentDueDate.year,
        widget.currentDueDate.month,
        widget.currentDueDate.day,
        now.hour,
        now.minute,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TaskMetadataPageHeader(title: 'Escolher horário'),
        SizedBox(
          height: 200,
          child: CupertinoDatePicker(
            mode: CupertinoDatePickerMode.time,
            use24hFormat: false,
            initialDateTime: _selectedTime,
            onDateTimeChanged: (d) => setState(() => _selectedTime = d),
          ),
        ),

        Padding(
          padding: const EdgeInsets.all(16),
          child: AppButton(
            text: 'Confirmar',
            onPressed: () {
              final d = widget.currentDueDate;
              final newDate = DateTime(
                d.year,
                d.month,
                d.day,
                _selectedTime.hour,
                _selectedTime.minute,
              );
              widget.onSelected(newDate, hasTime: true);
              FamilyModalSheet.of(context).popPage();
            },
          ),
        ),
      ],
    );
  }
}

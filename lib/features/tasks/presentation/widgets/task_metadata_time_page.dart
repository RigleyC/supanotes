import 'package:family_bottom_sheet/family_bottom_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:supanotes/shared/widgets/app_button.dart';

class TaskMetadataTimePage extends StatefulWidget {
  const TaskMetadataTimePage({
    super.key,
    required this.currentDueDate,
    required this.onSelected,
  });

  final DateTime currentDueDate;
  final void Function(DateTime date, {required bool hasTime}) onSelected;

  @override
  State<TaskMetadataTimePage> createState() => _TaskMetadataTimePageState();
}

class _TaskMetadataTimePageState extends State<TaskMetadataTimePage> {
  late DateTime _selectedTime;

  @override
  void initState() {
    super.initState();
    _selectedTime = widget.currentDueDate;
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

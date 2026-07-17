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

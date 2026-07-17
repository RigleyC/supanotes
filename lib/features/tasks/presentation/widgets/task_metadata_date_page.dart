import 'package:family_bottom_sheet/family_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:supanotes/core/utils/date_time_extensions.dart';
import 'package:supanotes/shared/widgets/app_selection_tile.dart';

import 'due_date_picker.dart' show QuickDueDate;

class TaskMetadataDatePage extends StatelessWidget {
  const TaskMetadataDatePage({
    super.key,
    required this.selected,
    required this.onSelected,
  });

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

import 'package:family_bottom_sheet/family_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:supanotes/core/utils/date_time_extensions.dart';
import 'package:supanotes/core/utils/app_haptics.dart';
import 'package:supanotes/shared/widgets/app_tile.dart';
import 'package:supanotes/shared/widgets/global_sheet.dart';

enum QuickDueDate {
  today,
  tomorrow,
  nextWeek;

  IconData get icon => Icons.calendar_month_rounded;

  String get label {
    return switch (this) {
      QuickDueDate.today => 'Hoje',
      QuickDueDate.tomorrow => 'Amanhã',
      QuickDueDate.nextWeek => 'Próxima semana',
    };
  }

  DateTime compute(DateTime now) {
    final today = now.startOfDay;
    return switch (this) {
      QuickDueDate.today => today,
      QuickDueDate.tomorrow => today.add(const Duration(days: 1)),
      QuickDueDate.nextWeek => today.add(const Duration(days: 7)),
    };
  }
}

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
    return GlobalSheetPage(
      title: 'Escolher data',
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.5,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: QuickDueDate.values.length,
                itemBuilder: (context, index) {
                  final option = QuickDueDate.values[index];
                  final date = option.compute(now);
                  return AppTile(
                    title: option.label,
                    leading: Icon(option.icon),
                    selected: selected != null && selected!.isSameDayAs(date),
                    onTap: () {
                      if (selected == null || !selected!.isSameDayAs(date)) {
                        AppHaptics.selectionChange();
                      }
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
          ),
        ),
      ),
    );
  }
}

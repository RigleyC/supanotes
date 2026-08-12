import 'package:family_bottom_sheet/family_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:supanotes/shared/widgets/app_selection_tile.dart';
import 'package:supanotes/shared/widgets/global_sheet.dart';

class TaskMetadataSelectionPage<T> extends StatelessWidget {
  const TaskMetadataSelectionPage({
    super.key,
    required this.title,
    required this.selected,
    required this.options,
    required this.noneLabel,
    required this.optionLabel,
    required this.optionIcon,
    required this.onSelected,
  });

  final String title;
  final T? selected;
  final Iterable<T> options;
  final String noneLabel;
  final String Function(T option) optionLabel;
  final IconData Function(T option) optionIcon;
  final ValueChanged<T?> onSelected;

  @override
  Widget build(BuildContext context) {
    void select(T? value) {
      onSelected(value);
      FamilyModalSheet.of(context).popPage();
    }

    return GlobalSheetPage(
      title: title,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.5,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSelectionTile(
                label: noneLabel,
                icon: Icons.do_not_disturb_on_outlined,
                isSelected: selected == null,
                onTap: () => select(null),
              ),
              for (final option in options)
                AppSelectionTile(
                  label: optionLabel(option),
                  icon: optionIcon(option),
                  isSelected: selected == option,
                  onTap: () => select(option),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

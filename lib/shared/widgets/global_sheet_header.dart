import 'package:family_bottom_sheet/family_bottom_sheet.dart';
import 'package:flutter/material.dart';

import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_icon_button.dart';

/// Fixed page header for a Family sheet page: title plus a close button that
/// delegates to [FamilyModalSheet.popPage].
class GlobalSheetHeader extends StatelessWidget {
  const GlobalSheetHeader({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          AppIconButton(
            tooltip: 'Fechar',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => FamilyModalSheet.of(context).popPage(),
          ),
        ],
      ),
    );
  }
}

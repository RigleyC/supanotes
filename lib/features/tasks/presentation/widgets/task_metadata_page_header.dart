import 'package:family_bottom_sheet/family_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';

class TaskMetadataPageHeader extends StatelessWidget {
  const TaskMetadataPageHeader({super.key, required this.title});

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
          IconButton(
            tooltip: 'Voltar',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => FamilyModalSheet.of(context).popPage(),
          ),
        ],
      ),
    );
  }
}

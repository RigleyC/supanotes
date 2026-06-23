import 'package:flutter/material.dart';

import 'package:supanotes/features/settings/domain/settings_strings.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_button.dart';

class SoulFooter extends StatelessWidget {
  const SoulFooter({
    super.key,
    required this.isSaving,
    required this.onSave,
    required this.onRestore,
  });

  final bool isSaving;
  final VoidCallback onSave;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: AppButton(
                text: SettingsStrings.restore,
                variant: AppButtonVariant.secondary,
                onPressed: onRestore,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppButton(
                text: isSaving ? SettingsStrings.saving : SettingsStrings.save,
                isLoading: isSaving,
                onPressed: onSave,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

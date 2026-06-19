import 'package:flutter/material.dart';
import 'package:supanotes/features/agent/domain/agent_strings.dart';
import 'package:supanotes/shared/widgets/app_button.dart';

class ConfirmationCard extends StatelessWidget {
  const ConfirmationCard({
    super.key,
    required this.label,
    required this.onApprove,
    required this.onCancel,
  });

  final String label;
  final VoidCallback onApprove;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  AgentStrings.confirmationRequiredTitle,
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(label, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  text: AgentStrings.actionCancel,
                  onPressed: onCancel,
                  variant: AppButtonVariant.secondary,
                  width: 100,
                ),
                const SizedBox(width: 8),
                AppButton(
                  text: AgentStrings.actionConfirm,
                  onPressed: onApprove,
                  variant: AppButtonVariant.primary,
                  width: 100,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

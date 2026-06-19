import 'package:flutter/material.dart';
import 'package:supanotes/features/agent/presentation/controllers/chat_controller.dart';
import 'package:supanotes/features/agent/presentation/widgets/shimmer_text.dart';

class AgentActionCard extends StatelessWidget {
  const AgentActionCard({
    super.key,
    required this.status,
    required this.label,
    this.message,
  });

  final ChatToolActionStatus status;
  final String label;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    Widget icon;
    Color? textColor;
    
    switch (status) {
      case ChatToolActionStatus.running:
        icon = const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
        break;
      case ChatToolActionStatus.completed:
      case ChatToolActionStatus.confirmed:
        icon = Icon(Icons.check_circle, size: 16, color: theme.colorScheme.primary);
        break;
      case ChatToolActionStatus.failed:
      case ChatToolActionStatus.cancelled:
        icon = Icon(Icons.error, size: 16, color: theme.colorScheme.error);
        textColor = theme.colorScheme.error;
        break;
      case ChatToolActionStatus.confirmationRequired:
        icon = Icon(Icons.warning, size: 16, color: theme.colorScheme.primary);
        break;
    }

    Widget header = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: textColor ?? theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );

    if (status == ChatToolActionStatus.running) {
      header = ShimmerText(child: header);
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          if (message != null && message!.isNotEmpty && status == ChatToolActionStatus.failed) ...[
            const SizedBox(height: 4),
            Text(
              message!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ]
        ],
      ),
    );
  }
}

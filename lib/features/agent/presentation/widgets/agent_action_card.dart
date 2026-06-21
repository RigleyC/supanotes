import 'package:flutter/material.dart';
import 'package:supanotes/features/agent/presentation/controllers/chat_controller.dart';
import 'package:supanotes/features/agent/presentation/widgets/skeleton_status_card.dart';

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
    
    IconData? icon;
    Color? iconColor;
    
    switch (status) {
      case ChatToolActionStatus.running:
        icon = Icons.sync;
        break;
      case ChatToolActionStatus.completed:
      case ChatToolActionStatus.confirmed:
        icon = Icons.check_circle;
        iconColor = theme.colorScheme.primary;
        break;
      case ChatToolActionStatus.failed:
      case ChatToolActionStatus.cancelled:
        icon = Icons.error;
        iconColor = theme.colorScheme.error;
        break;
      case ChatToolActionStatus.confirmationRequired:
        icon = Icons.warning;
        iconColor = theme.colorScheme.primary;
        break;
    }

    final isRunning = status == ChatToolActionStatus.running;

    return SkeletonStatusCard(
      label: label,
      icon: icon,
      iconColor: iconColor,
      isShimmering: isRunning,
      showSkeletonLines: isRunning,
      padding: const EdgeInsets.all(12),
    );
  }
}

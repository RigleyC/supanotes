import 'package:flutter/material.dart';
import 'package:supanotes/features/agent/presentation/controllers/chat_controller.dart';
import 'package:supanotes/features/agent/presentation/widgets/shimmer_text.dart';
import 'package:supanotes/shared/widgets/app_button.dart';

class AgentActionTimelineCard extends StatefulWidget {
  const AgentActionTimelineCard({
    super.key,
    required this.actions,
    this.onResolveConfirmation,
  });

  final List<ChatToolAction> actions;
  final void Function(String confirmationId, {required bool approved})?
  onResolveConfirmation;

  @override
  State<AgentActionTimelineCard> createState() =>
      _AgentActionTimelineCardState();
}

class _AgentActionTimelineCardState extends State<AgentActionTimelineCard> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _expanded = widget.actions.any(
      (a) =>
          a.status == ChatToolActionStatus.running ||
          a.status == ChatToolActionStatus.confirmationRequired,
    );
  }

  @override
  void didUpdateWidget(covariant AgentActionTimelineCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hasActive = widget.actions.any(
      (a) =>
          a.status == ChatToolActionStatus.running ||
          a.status == ChatToolActionStatus.confirmationRequired,
    );
    final hadActive = oldWidget.actions.any(
      (a) =>
          a.status == ChatToolActionStatus.running ||
          a.status == ChatToolActionStatus.confirmationRequired,
    );
    if (hasActive && !hadActive) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isAnyRunning = widget.actions.any(
      (a) => a.status == ChatToolActionStatus.running,
    );
    final isAnyConfirmation = widget.actions.any(
      (a) => a.status == ChatToolActionStatus.confirmationRequired,
    );

    String headerText = 'Etapas executadas';
    if (isAnyRunning) {
      headerText = 'Executando ações...';
    } else if (isAnyConfirmation) {
      headerText = 'Confirmação necessária';
    }

    final iconColor = isAnyConfirmation
        ? theme.colorScheme.primary
        : (isAnyRunning
              ? theme.colorScheme.secondary
              : theme.colorScheme.primary);

    Widget headerIcon;
    if (isAnyRunning) {
      headerIcon = SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          valueColor: AlwaysStoppedAnimation<Color>(iconColor),
        ),
      );
    } else if (isAnyConfirmation) {
      headerIcon = Icon(Icons.help_outline, size: 14, color: iconColor);
    } else {
      headerIcon = Icon(Icons.check_circle_outline, size: 14, color: iconColor);
    }

    final backgroundColor = isDark
        ? const Color(0xFF1C1C1E)
        : const Color(0xFFF2F2F7);

    Widget headerContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        headerIcon,
        const SizedBox(width: 8),
        Text(
          headerText,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 4),
        Icon(
          _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ],
    );

    if (isAnyRunning) {
      headerContent = ShimmerText(child: headerContent);
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: headerContent,
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.only(
                      left: 12,
                      right: 12,
                      bottom: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(height: 1, thickness: 0.5),
                        const SizedBox(height: 8),
                        ...widget.actions.map(
                          (action) => _buildActionRow(context, action),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow(BuildContext context, ChatToolAction action) {
    final theme = Theme.of(context);

    Widget statusIcon;
    Color? textColor;

    switch (action.status) {
      case ChatToolActionStatus.running:
        statusIcon = SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(
              theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        );
        break;
      case ChatToolActionStatus.completed:
      case ChatToolActionStatus.confirmed:
        statusIcon = Icon(
          Icons.check_circle_outline,
          size: 14,
          color: theme.colorScheme.primary,
        );
        break;
      case ChatToolActionStatus.failed:
      case ChatToolActionStatus.cancelled:
        statusIcon = Icon(
          Icons.error_outline,
          size: 14,
          color: theme.colorScheme.error,
        );
        textColor = theme.colorScheme.error;
        break;
      case ChatToolActionStatus.confirmationRequired:
        statusIcon = Icon(
          Icons.help_outline,
          size: 14,
          color: theme.colorScheme.primary,
        );
        break;
    }

    Widget row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 3.0), child: statusIcon),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                action.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: textColor ?? theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                'ferramenta: ${action.name}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.6,
                  ),
                  fontStyle: FontStyle.italic,
                ),
              ),
              if (action.message != null &&
                  action.message!.isNotEmpty &&
                  action.status == ChatToolActionStatus.failed) ...[
                const SizedBox(height: 4),
                Text(
                  action.message!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              if (action.status == ChatToolActionStatus.confirmationRequired &&
                  action.confirmationId != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    AppButton(
                      text: 'Confirmar',
                      onPressed: () => widget.onResolveConfirmation?.call(
                        action.confirmationId!,
                        approved: true,
                      ),
                      variant: AppButtonVariant.primary,
                      width: 100,
                    ),
                    const SizedBox(width: 8),
                    AppButton(
                      text: 'Cancelar',
                      onPressed: () => widget.onResolveConfirmation?.call(
                        action.confirmationId!,
                        approved: false,
                      ),
                      variant: AppButtonVariant.secondary,
                      width: 100,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );

    if (action.status == ChatToolActionStatus.running) {
      row = ShimmerText(child: row);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: row,
    );
  }
}

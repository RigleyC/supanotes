import 'package:flutter/material.dart';

import 'package:supanotes/shared/theme/app_spacing.dart';

/// Three-dot "agent is thinking" indicator with a small bounce animation.
///
/// Used in the chat list while [ChatController] has `isLoading == true`
/// after the user has sent a message (i.e. the agent is composing a
/// reply, not on the initial history load).
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  static const Duration _period = Duration(milliseconds: 900);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _period)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List<Widget>.generate(3, (i) {
              final phase = (_controller.value * 3 - i).clamp(0.0, 1.0);
              final bounce = 1.0 - (phase * 2 - 1).abs().clamp(0.0, 1.0);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Transform.translate(
                  offset: Offset(0, -8 * bounce),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

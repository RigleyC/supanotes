import 'package:flutter/material.dart';
import 'package:supanotes/features/agent/presentation/widgets/shimmer_text.dart';

class CollapsibleThinkingCard extends StatefulWidget {
  const CollapsibleThinkingCard({
    super.key,
    required this.thinkingText,
    required this.isFinished,
  });

  final String thinkingText;
  final bool isFinished;

  @override
  State<CollapsibleThinkingCard> createState() => _CollapsibleThinkingCardState();
}

class _CollapsibleThinkingCardState extends State<CollapsibleThinkingCard> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // Start expanded while thinking is in progress
    _expanded = !widget.isFinished;
  }

  @override
  void didUpdateWidget(covariant CollapsibleThinkingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If thinking completes, collapse it
    if (oldWidget.isFinished != widget.isFinished && widget.isFinished) {
      setState(() {
        _expanded = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final headerText = widget.isFinished ? 'Raciocínio concluído' : 'Pensando…';

    final iconColor = widget.isFinished
        ? theme.colorScheme.primary
        : theme.colorScheme.secondary;

    final icon = widget.isFinished
        ? Icon(Icons.check_circle_outline, size: 16, color: iconColor)
        : Icon(Icons.lightbulb_outline, size: 16, color: iconColor);

    Widget headerContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 8),
        Text(
          headerText,
          style: theme.textTheme.bodySmall?.copyWith(
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

    if (!widget.isFinished) {
      headerContent = ShimmerText(child: headerContent);
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerLowest
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    child: Text(
                      widget.thinkingText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity, height: 0),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

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

    final headerText = widget.isFinished ? 'Raciocínio concluído' : 'Pensando...';
    final iconColor = widget.isFinished ? theme.colorScheme.primary : theme.colorScheme.secondary;

    final Widget icon = widget.isFinished
        ? Icon(Icons.check_circle_outline, size: 16, color: iconColor)
        : SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation<Color>(iconColor),
            ),
          );

    final backgroundColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);

    final headerContent = Row(
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

    final textStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
      height: 1.5,
      fontStyle: widget.isFinished ? FontStyle.normal : FontStyle.italic,
    ) ?? const TextStyle();

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
                    child: widget.thinkingText.isEmpty && !widget.isFinished
                        ? Text(
                            'Escrevendo raciocínio...',
                            style: textStyle.copyWith(
                              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                          )
                        : Text(
                            widget.thinkingText,
                            style: textStyle,
                          ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

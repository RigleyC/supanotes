import 'package:flutter/material.dart';
import 'package:supanotes/features/agent/presentation/widgets/shimmer_text.dart';

class SkeletonStatusCard extends StatelessWidget {
  const SkeletonStatusCard({
    super.key,
    required this.label,
    this.icon,
    this.iconColor,
    this.isShimmering = true,
    this.showSkeletonLines = true,
    this.padding = const EdgeInsets.all(14),
  });

  final String label;
  final IconData? icon;
  final Color? iconColor;
  final bool isShimmering;
  final bool showSkeletonLines;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor = isDark ? const Color(0xFF111111) : const Color(0xFFF7F7F8);
    final skeletonColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E5E5);

    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
    );

    Widget textWidget = Text(label, style: labelStyle);
    if (isShimmering) {
      textWidget = ShimmerText(child: textWidget);
    }

    Widget header = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: iconColor ?? theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
        ],
        textWidget,
      ],
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          if (showSkeletonLines) ...[
            const SizedBox(height: 12),
            _buildSkeletonLine(width: 180, height: 8, color: skeletonColor),
            const SizedBox(height: 8),
            _buildSkeletonLine(width: 140, height: 8, color: skeletonColor),
            const SizedBox(height: 8),
            _buildSkeletonLine(width: 200, height: 8, color: skeletonColor),
          ],
        ],
      ),
    );
  }

  Widget _buildSkeletonLine({required double width, required double height, required Color color}) {
    final line = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );

    if (isShimmering) {
      return ShimmerText(child: line);
    }
    return line;
  }
}

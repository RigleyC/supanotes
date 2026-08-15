import 'package:flutter/material.dart';

import 'package:supanotes/core/utils/app_haptics.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_press_scale.dart';

/// Shared row for settings and task metadata flows.
class AppTile extends StatefulWidget {
  const AppTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.enableHaptics = true,
    this.enabled = true,
    this.selected = false,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.xs,
    ),
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enableHaptics;
  final bool enabled;
  final bool selected;
  final EdgeInsetsGeometry contentPadding;

  @override
  State<AppTile> createState() => _AppTileState();
}

class _AppTileState extends State<AppTile> {
  bool _pressed = false;

  bool get _interactive => widget.enabled && widget.onTap != null;

  void _setPressed(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = !widget.enabled
        ? scheme.onSurface.withValues(alpha: 0.38)
        : widget.selected
        ? scheme.primary
        : scheme.onSurface;
    final leadingColor = !widget.enabled
        ? scheme.onSurface.withValues(alpha: 0.38)
        : widget.selected
        ? scheme.primary
        : scheme.onSurfaceVariant;
    final titleStyle = (theme.textTheme.titleSmall ?? const TextStyle())
        .copyWith(
          color: foreground,
          fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
        );
    final subtitleStyle = theme.textTheme.bodyMedium?.copyWith(
      color: widget.enabled
          ? scheme.onSurfaceVariant
          : scheme.onSurface.withValues(alpha: 0.38),
    );
    final leading = switch (widget.leading) {
      null => null,
      final Icon icon =>
        widget.selected
            ? Icon(
                icon.icon,
                key: icon.key,
                size: icon.size ?? AppSpacing.tileIconSize,
                fill: icon.fill,
                weight: icon.weight,
                grade: icon.grade,
                opticalSize: icon.opticalSize,
                color: leadingColor,
                shadows: icon.shadows,
                semanticLabel: icon.semanticLabel,
                textDirection: icon.textDirection,
                applyTextScaling: icon.applyTextScaling,
                blendMode: icon.blendMode,
                fontWeight: icon.fontWeight,
              )
            : IconTheme.merge(
                data: IconThemeData(
                  color: leadingColor,
                  size: AppSpacing.tileIconSize,
                ),
                child: icon,
              ),
      final leadingWidget => IconTheme.merge(
        data: IconThemeData(color: leadingColor, size: AppSpacing.tileIconSize),
        child: leadingWidget,
      ),
    };
    final trailing = widget.selected && widget.trailing == null
        ? Icon(
            Icons.check_rounded,
            size: AppSpacing.tileIconSize,
            color: foreground,
          )
        : widget.trailing;
    final interactive = _interactive;

    return Semantics(
      button: widget.onTap != null,
      enabled: widget.enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: interactive
            ? () {
                if (widget.enableHaptics) AppHaptics.controlTap();
                widget.onTap!();
              }
            : null,
        onTapDown: interactive ? (_) => _setPressed(true) : null,
        onTapUp: interactive ? (_) => _setPressed(false) : null,
        onTapCancel: interactive ? () => _setPressed(false) : null,
        child: AppPressScale(
          pressed: interactive && _pressed,
          child: Container(
            constraints: const BoxConstraints(minHeight: AppSpacing.tileHeight),
            padding: widget.contentPadding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (leading != null) ...[
                  leading,
                  const SizedBox(width: AppSpacing.md),
                ],
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title, style: titleStyle),
                      if (widget.subtitle != null)
                        Text(widget.subtitle!, style: subtitleStyle),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  trailing,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
    this.subtitleWidget,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
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
  final Widget? subtitleWidget;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enableHaptics;
  final bool enabled;
  final bool selected;
  final EdgeInsetsGeometry contentPadding;

  @override
  State<AppTile> createState() => _AppTileState();
}

class _AppTileState extends State<AppTile> {
  bool _pressed = false;

  bool get _interactive =>
      widget.enabled && (widget.onTap != null || widget.onLongPress != null);

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
    final leading = widget.leading != null
        ? IconTheme.merge(
            data: IconThemeData(
              color: leadingColor,
              size: AppSpacing.tileIconSize,
            ),
            child: widget.leading!,
          )
        : null;
    final trailing = widget.selected && widget.trailing == null
        ? Icon(
            Icons.check_rounded,
            size: AppSpacing.tileIconSize,
            color: foreground,
          )
        : widget.trailing;
    final subtitle = widget.subtitleWidget ??
        (widget.subtitle != null
            ? Text(
                widget.subtitle!,
                style: subtitleStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null);
    final interactive = _interactive;

    return Semantics(
      button: widget.onTap != null || widget.onLongPress != null,
      enabled: widget.enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: interactive ? (_) => _setPressed(true) : null,
        onTapUp: interactive ? (_) => _setPressed(false) : null,
        onTapCancel: interactive ? () => _setPressed(false) : null,
        onTap: widget.enabled && widget.onTap != null
            ? () {
                if (widget.enableHaptics) AppHaptics.controlTap();
                widget.onTap!();
              }
            : null,
        onLongPressDown: interactive ? (_) => _setPressed(true) : null,
        onLongPressEnd: interactive ? (_) => _setPressed(false) : null,
        onLongPressCancel: interactive ? () => _setPressed(false) : null,
        onLongPress: widget.enabled && widget.onLongPress != null
            ? () {
                if (widget.enableHaptics) AppHaptics.longPress();
                widget.onLongPress!();
              }
            : null,
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
                      Text(
                        widget.title,
                        style: titleStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      ?subtitle,
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

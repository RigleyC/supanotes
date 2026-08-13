import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:motor/motor.dart';

import 'package:supanotes/shared/theme/app_spacing.dart';

class ToolbarButton extends StatefulWidget {
  const ToolbarButton({
    super.key,
    this.icon,
    this.svgAsset,
    this.semanticLabel,
    this.spacious = false,
    required this.isActive,
    this.onPressed,
  }) : assert(
         icon != null || svgAsset != null,
         'Provide either an icon or an svgAsset.',
       );

  final IconData? icon;
  final String? svgAsset;
  final String? semanticLabel;
  final bool spacious;
  final bool isActive;
  final VoidCallback? onPressed;

  @override
  State<ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<ToolbarButton>
    with TickerProviderStateMixin {
  late final SingleMotionController _activeMotion;
  late final SingleMotionController _iconMotion;
  late final Listenable _motion;

  @override
  void initState() {
    super.initState();
    _activeMotion = SingleMotionController(
      motion: const MaterialSpringMotion.standardEffectsFast(),
      vsync: this,
      initialValue: widget.isActive ? 1 : 0,
    );
    _iconMotion = SingleMotionController(
      motion: const MaterialSpringMotion.standardEffectsFast(),
      vsync: this,
      initialValue: 1,
    );
    _motion = Listenable.merge([_activeMotion, _iconMotion]);
  }

  @override
  void didUpdateWidget(ToolbarButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _animateTo(_activeMotion, widget.isActive ? 1 : 0);
    }
    if (oldWidget.icon != widget.icon ||
        oldWidget.svgAsset != widget.svgAsset) {
      _iconMotion.value = 0;
      _animateTo(_iconMotion, 1);
    }
  }

  @override
  void dispose() {
    _activeMotion.dispose();
    _iconMotion.dispose();
    super.dispose();
  }

  Future<void> _animateTo(
    SingleMotionController controller,
    double target,
  ) async {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      controller.value = target;
      return;
    }
    try {
      await controller.animateTo(target).orCancel;
    } on TickerCanceled {
      // The controller is disposed with the toolbar.
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _motion,
      builder: (_, _) => _ToolbarButtonVisual(
        icon: widget.icon,
        svgAsset: widget.svgAsset,
        semanticLabel: widget.semanticLabel,
        spacious: widget.spacious,
        onPressed: widget.onPressed,
        activeProgress: _activeMotion.value.clamp(0.0, 1.0),
        iconProgress: _iconMotion.value.clamp(0.0, 1.0),
      ),
    );
  }
}

class _ToolbarButtonVisual extends StatelessWidget {
  const _ToolbarButtonVisual({
    required this.icon,
    required this.svgAsset,
    required this.semanticLabel,
    required this.spacious,
    required this.onPressed,
    required this.activeProgress,
    required this.iconProgress,
  });

  final IconData? icon;
  final String? svgAsset;
  final String? semanticLabel;
  final bool spacious;
  final VoidCallback? onPressed;
  final double activeProgress;
  final double iconProgress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final inactiveColor = onPressed == null
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : colorScheme.onSurface;
    final foreground = Color.lerp(
      inactiveColor,
      colorScheme.primary,
      activeProgress,
    )!;
    final background = colorScheme.primary.withValues(
      alpha: 0.12 * activeProgress,
    );
    final buttonIcon = icon != null
        ? Icon(icon, size: spacious ? 28 : 26, color: foreground)
        : SvgPicture.asset(
            svgAsset!,
            width: spacious ? 26 : 24,
            height: spacious ? 26 : 24,
            colorFilter: ColorFilter.mode(foreground, BlendMode.srcIn),
          );

    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        onTap: onPressed,
        child: Container(
          constraints: BoxConstraints(
            minWidth: spacious ? 44 : 36,
            minHeight: spacious ? 44 : 36,
          ),
          alignment: Alignment.center,
          padding: EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Transform.scale(
            scale: 0.96 + (0.04 * activeProgress),
            child: Opacity(
              opacity: 0.7 + (0.3 * iconProgress),
              child: Transform.scale(
                scale: 0.9 + (0.1 * iconProgress),
                child: buttonIcon,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ToolbarDivider extends StatelessWidget {
  const ToolbarDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

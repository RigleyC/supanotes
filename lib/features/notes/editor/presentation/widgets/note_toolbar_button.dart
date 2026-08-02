part of 'note_toolbar.dart';

class _ToolbarButton extends StatefulWidget {
  const _ToolbarButton({
    this.icon,
    this.svgAsset,
    this.semanticLabel,
    this.compact = false,
    required this.isActive,
    this.onPressed,
  }) : assert(
         icon != null || svgAsset != null,
         'Provide either an icon or an svgAsset.',
       );

  final IconData? icon;
  final String? svgAsset;
  final String? semanticLabel;
  final bool compact;
  final bool isActive;
  final VoidCallback? onPressed;

  @override
  State<_ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<_ToolbarButton>
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
  void didUpdateWidget(_ToolbarButton oldWidget) {
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
      builder: (context, child) {
        final colorScheme = Theme.of(context).colorScheme;
        final activeProgress = _activeMotion.value.clamp(0.0, 1.0);
        final iconProgress = _iconMotion.value.clamp(0.0, 1.0);
        final inactiveColor = widget.onPressed == null
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

        final icon = widget.icon != null
            ? Icon(
                widget.icon,
                size: widget.compact ? 22 : 26,
                color: foreground,
              )
            : SvgPicture.asset(
                widget.svgAsset!,
                width: widget.compact ? 20 : 24,
                height: widget.compact ? 20 : 24,
                colorFilter: ColorFilter.mode(foreground, BlendMode.srcIn),
              );

        return Semantics(
          button: true,
          enabled: widget.onPressed != null,
          label: widget.semanticLabel,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            onTap: widget.onPressed,
            child: Container(
              constraints: BoxConstraints(
                minWidth: widget.compact ? 32 : 36,
                minHeight: widget.compact ? 32 : 36,
              ),
              alignment: Alignment.center,
              padding: EdgeInsets.all(widget.compact ? 2 : AppSpacing.xs),
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
                    child: icon,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

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

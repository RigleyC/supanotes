import 'package:flutter/material.dart';

/// Animated circular checkbox used by the [TaskTile] family.
///
/// The whole circle is an [AnimatedContainer] that tweens between an
/// outlined and a filled primary state. The inner [Icons.check] is an
/// [AnimatedScale] that pops in once the circle fills, giving the tap
/// a small but satisfying "stamp" feel.
class TaskCheckbox extends StatelessWidget {
  const TaskCheckbox({
    super.key,
    required this.checked,
    required this.onChanged,
    this.size = 24.0,
    this.accentColor,
  });

  final bool checked;
  final ValueChanged<bool> onChanged;
  final double size;
  /// When provided, overrides [ColorScheme.primary] as the active colour.
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = accentColor ?? scheme.primary;
    final fillColor = checked ? active : Colors.transparent;
    final borderColor = checked
        ? active
        : scheme.outline.withValues(alpha: 0.6);

    return Semantics(
      checked: checked,
      label: 'Tarefa ${checked ? 'concluída' : 'pendente'}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!checked),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: fillColor,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 2),
          ),
          child: Center(
            child: AnimatedScale(
              scale: checked ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutBack,
              child: Icon(
                Icons.check,
                size: size * 0.65,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

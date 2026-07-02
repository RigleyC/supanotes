import 'package:flutter/material.dart';

import '../../../../shared/theme/app_spacing.dart';

/// Tappable field that opens the platform's native [showTimePicker]
/// and renders the current selection as `HH:mm` next to a clock icon.
///
/// The widget is intentionally controlled (no internal state) so the
/// parent owns the canonical [TimeOfDay] and the picker cannot drift
/// out of sync.
class TimePickerField extends StatelessWidget {
  const TimePickerField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final TimeOfDay value;
  final ValueChanged<TimeOfDay> onChanged;

  Future<void> _open(BuildContext context) async {
    final picked = await showTimePicker(context: context, initialTime: value);
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.access_time, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
              Text(
                _format(value),
                style: textTheme.titleMedium?.copyWith(
                  color: scheme.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _format(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

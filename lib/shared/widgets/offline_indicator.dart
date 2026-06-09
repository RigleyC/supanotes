import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync/sync_state.dart';
import '../theme/app_spacing.dart';

/// Banner that reflects the current [SyncStatus].
///
/// In its default full-width mode it is meant to be dropped at the top
/// of a scroll view. In `floating: true` mode it renders as a rounded
/// pill suitable for an overlay at the bottom of a Scaffold (does not
/// consume the full width and respects horizontal margins).
class OfflineIndicator extends ConsumerWidget {
  const OfflineIndicator({super.key, this.floating = false});

  /// When true, renders as a rounded floating pill instead of a
  /// full-width bar.
  final bool floating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(syncStateProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final labelSmall = Theme.of(context).textTheme.labelSmall;

    switch (state.status) {
      case SyncStatus.idle:
      case SyncStatus.syncing:
        // Periodic background syncs happen every 30s; flashing a banner
        // for them is noise. Only surface stable, actionable states.
        return const SizedBox.shrink();
      case SyncStatus.offline:
        return _Banner(
          color: colorScheme.error,
          textColor: colorScheme.onError,
          label: 'Modo offline. As alterações serão sincronizadas quando reconectado.',
          fontSize: labelSmall?.fontSize ?? 12,
          floating: floating,
        );
      case SyncStatus.error:
        return _Banner(
          color: colorScheme.tertiary,
          textColor: colorScheme.onTertiary,
          label: 'Erro de sincronização: ${state.errorMessage ?? "desconhecido"}',
          fontSize: labelSmall?.fontSize ?? 12,
          floating: floating,
        );
    }
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.color,
    required this.textColor,
    required this.label,
    required this.fontSize,
    required this.floating,
  });

  final Color color;
  final Color textColor;
  final String label;
  final double fontSize;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      color: textColor,
      fontSize: fontSize,
      fontWeight: floating ? FontWeight.w500 : null,
    );

    if (floating) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Text(label, textAlign: TextAlign.center, style: textStyle),
      );
    }

    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Text(label, textAlign: TextAlign.center, style: textStyle),
    );
  }
}

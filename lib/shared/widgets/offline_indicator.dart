import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/sync/sync_state.dart';
import '../theme/app_spacing.dart';

class OfflineIndicator extends ConsumerWidget {
  const OfflineIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(syncStateProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final labelSmall = Theme.of(context).textTheme.labelSmall;

    switch (state.status) {
      case SyncStatus.idle:
        return const SizedBox.shrink();
      case SyncStatus.syncing:
        return Container(
          width: double.infinity,
          color: colorScheme.primary,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Text(
            'Syncing...',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colorScheme.onPrimary,
              fontSize: labelSmall?.fontSize ?? 12,
            ),
          ),
        );
      case SyncStatus.offline:
        return Container(
          width: double.infinity,
          color: colorScheme.error,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Text(
            'Offline mode. Changes will sync when reconnected.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colorScheme.onError,
              fontSize: labelSmall?.fontSize ?? 12,
            ),
          ),
        );
      case SyncStatus.error:
        return Container(
          width: double.infinity,
          color: colorScheme.tertiary,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Text(
            'Sync error: ${state.errorMessage ?? "unknown"}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colorScheme.onTertiary,
              fontSize: labelSmall?.fontSize ?? 12,
            ),
          ),
        );
    }
  }
}

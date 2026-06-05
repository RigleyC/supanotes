import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/sync/sync_state.dart';

class OfflineIndicator extends ConsumerWidget {
  const OfflineIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(syncStateProvider);

    switch (state.status) {
      case SyncStatus.idle:
        return const SizedBox.shrink();
      case SyncStatus.syncing:
        return Container(
          width: double.infinity,
          color: Colors.blueAccent,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: const Text(
            'Syncing...',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        );
      case SyncStatus.offline:
        return Container(
          width: double.infinity,
          color: Colors.redAccent,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: const Text(
            'Offline mode. Changes will sync when reconnected.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        );
      case SyncStatus.error:
        return Container(
          width: double.infinity,
          color: Colors.orangeAccent,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'Sync error: ${state.errorMessage ?? "unknown"}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        );
    }
  }
}

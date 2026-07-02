/// Reactive state for the background [SyncService].
///
/// Exposed via [syncStateProvider] so the UI can render a status banner
/// (`OfflineIndicator`) without reaching into the service directly. The
/// provider is a `NotifierProvider` so widgets can `ref.watch` the
/// current [SyncState] and react to transitions.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Coarse-grained sync status surfaced to the UI.
enum SyncStatus {
  /// No sync in flight and no error to report.
  idle,

  /// A push/pull round is currently running.
  syncing,

  /// The device is offline; changes are queued locally and will sync
  /// when connectivity is restored.
  offline,

  /// The last attempt failed with a non-connectivity error.
  error,
}

/// Immutable snapshot of the sync subsystem.
class SyncState {
  const SyncState({required this.status, this.lastSyncedAt, this.errorMessage});

  final SyncStatus status;
  final DateTime? lastSyncedAt;
  final String? errorMessage;

  SyncState copyWith({
    SyncStatus? status,
    DateTime? lastSyncedAt,
    String? errorMessage,
    bool clearError = false,
    bool clearLastSynced = false,
  }) {
    return SyncState(
      status: status ?? this.status,
      lastSyncedAt: clearLastSynced
          ? null
          : (lastSyncedAt ?? this.lastSyncedAt),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Mutable notifier owned by the [SyncService] — widgets read it via
/// [syncStateProvider] and never mutate it directly.
class SyncStateNotifier extends Notifier<SyncState> {
  @override
  SyncState build() {
    return const SyncState(status: SyncStatus.idle);
  }

  void markSyncing() {
    state = state.copyWith(status: SyncStatus.syncing, clearError: true);
  }

  void markSynced(DateTime when) {
    state = SyncState(status: SyncStatus.idle, lastSyncedAt: when);
  }

  void markOffline() {
    state = state.copyWith(status: SyncStatus.offline, clearError: true);
  }

  void markError(String message) {
    state = state.copyWith(status: SyncStatus.error, errorMessage: message);
  }
}

final syncStateProvider = NotifierProvider<SyncStateNotifier, SyncState>(
  SyncStateNotifier.new,
);

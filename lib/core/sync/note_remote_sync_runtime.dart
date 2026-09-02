import 'dart:async';
import 'dart:developer' as dev;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/sync/note_remote_sync_coordinator.dart';
import 'package:supanotes/core/sync/sync_feed_client.dart';
import 'package:supanotes/core/sync/sync_inbox_store.dart';
import 'package:supanotes/core/sync/sync_retry_policy.dart';
import 'package:supanotes/features/notes/catalog/data/note_catalog_sync.dart';
import 'package:supanotes/features/notes/catalog/data/remote_note_change_applier.dart';
import 'package:supanotes/features/notes/catalog/model/remote_note_metadata.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';

typedef RemoteNoteMetadataLoader =
    Future<RemoteNoteMetadata> Function(
      String noteId,
    );

final syncInboxStoreProvider = Provider.autoDispose<SyncInboxStore>((ref) {
  return SyncInboxStore(ref.watch(appDatabaseProvider));
});

final syncChangesFetcherProvider = Provider<SyncChangesFetcher>((ref) {
  final client = SyncFeedClient(ref.watch(apiClientProvider));
  return client.fetchChanges;
});

final remoteNoteMetadataLoaderProvider = Provider<RemoteNoteMetadataLoader>((
  ref,
) {
  final api = ref.watch(apiClientProvider);
  return (noteId) async {
    final response = await api.get<Map<String, dynamic>>('/notes/$noteId');
    final data = response.data;
    if (data == null) {
      throw const FormatException('Remote note metadata response is empty');
    }
    return RemoteNoteMetadata.fromJson(data);
  };
});

final noteRemoteSyncCoordinatorProvider =
    Provider.autoDispose<NoteRemoteSyncCoordinator?>((ref) {
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null || userId.isEmpty) return null;

      final database = ref.watch(appDatabaseProvider);
      final catalog = ref.watch(noteCatalogSyncServiceProvider);
      final activityTracker = ref.watch(noteSessionActivityTrackerProvider);
      final store = ref.watch(syncInboxStoreProvider);
      final metadataLoader = ref.watch(remoteNoteMetadataLoaderProvider);
      final metadataApplier = RemoteNoteChangeApplier(
        database: database,
        catalogSync: catalog,
        userId: userId,
      );

      Future<void> syncPending(String noteId) async {
        final result = await ref
            .read(noteOperationsSyncServiceProvider)
            .syncPending(noteId);
        if (result.isBlocked) {
          throw StateError('Remote sync blocked for note $noteId');
        }
      }

      Future<void> pollAndReconcile(String noteId) async {
        final result = await ref
            .read(noteOperationsSyncServiceProvider)
            .pollAndReconcile(noteId);
        if (result.isBlocked) {
          throw StateError('Remote reconciliation blocked for note $noteId');
        }
      }

      Future<void> hydrateRemote(String noteId) async {
        try {
          final metadata = await metadataLoader(noteId);
          await metadataApplier.apply(metadata);
        } on DioException catch (error) {
          if (error.response?.statusCode == 404) {
            await database.deleteNoteData(noteId);
            return;
          }
          rethrow;
        }
      }

      final coordinator = NoteRemoteSyncCoordinator(
        userId: userId,
        store: store,
        fetchChanges: ref.watch(syncChangesFetcherProvider),
        bootstrapCatalog: () => catalog.pullRemoteNotes(userId),
        isNoteActive: activityTracker.isActive,
        syncPending: syncPending,
        confirmedRevision: (noteId) async =>
            (await ref
                    .read(noteOperationsSyncServiceProvider)
                    .getConfirmedDocument(noteId))
                ?.revision,
        pollAndReconcile: pollAndReconcile,
        hydrateRemote: hydrateRemote,
        deleteLocal: database.deleteNoteData,
      );

      ref.onDispose(() {
        unawaited(coordinator.dispose());
      });
      return coordinator;
    });

/// Incremental app-scoped remote synchronization.
///
/// The first successful run performs one complete catalog bootstrap at a
/// stable change-feed watermark. Subsequent runs fetch only changes after the
/// durable cursor and apply them through the local inbox.
final noteRemoteSyncRuntimeProvider = StreamProvider.autoDispose<void>((
  ref,
) async* {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null || userId.isEmpty) return;

  final catalog = ref.watch(noteCatalogSyncServiceProvider);
  final coordinator = ref.watch(noteRemoteSyncCoordinatorProvider);
  if (coordinator == null) return;

  final connectivitySubscription = ref
      .watch(noteOutboxConnectivityChangesProvider)
      .listen((results) {
        if (results.any((result) => result != ConnectivityResult.none)) {
          coordinator.wake();
        }
      });
  ref.onDispose(() {
    unawaited(connectivitySubscription.cancel());
  });

  var failureAttempt = 0;
  while (true) {
    try {
      await catalog.pushDeletedNotes();
      await catalog.pushDirtyPreferences();
      await coordinator.syncOnce();
      await catalog.pushDirtyNoteIcons();
      failureAttempt = 0;
      yield null;
    } catch (error, stackTrace) {
      if (_isUnauthenticated(error)) {
        dev.log('[RemoteSync] Stopped (unauthenticated)');
        break;
      }
      dev.log(
        '[RemoteSync] Incremental sync failed',
        error: error,
        stackTrace: stackTrace,
      );
      failureAttempt++;
    }
    await Future<void>.delayed(_remoteSyncDelay(failureAttempt));
  }
});

Duration _remoteSyncDelay(int failureAttempt) {
  if (failureAttempt == 0) return const Duration(seconds: 2);
  return syncRetryDelayForAttempt(failureAttempt);
}

bool _isUnauthenticated(Object error) {
  if (error is NoteOperationsException) return error.statusCode == 401;
  return error is DioException && error.response?.statusCode == 401;
}

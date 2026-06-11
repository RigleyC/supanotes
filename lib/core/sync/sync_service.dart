/// Push / pull loop for the local-first notes database.
///
/// `SyncService` is a long-lived object whose lifetime is tied to the
/// authenticated session — see `main.dart`, which calls [start] when the
/// auth controller emits `AuthAuthenticated` and [dispose] when it emits
/// `AuthUnauthenticated`. The service does not auto-start in its
/// constructor; that is intentional so the periodic [Timer] only runs
/// while the user is signed in.
///
/// State is exposed to the UI through [syncStateProvider]; the service
/// just updates the notifier and lets widgets react.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database.dart';
import '../di/providers.dart';
import 'connectivity_monitor.dart';
import 'sync_mapper.dart';
import 'sync_repository.dart';
import 'sync_state.dart';

/// SharedPreferences key under which the last successful sync
/// timestamp is persisted across app launches.
const String _kLastSyncedAtPref = 'last_synced_at';

final syncServiceProvider = Provider<SyncService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final apiClient = ref.watch(apiClientProvider);
  final connectivity = ref.watch(connectivityMonitorProvider);
  final notifier = ref.watch(syncStateProvider.notifier);

  final repo = SyncRepository(apiClient: apiClient);
  final mapper = SyncMapper();

  final service = SyncService(
    db: db,
    repo: repo,
    mapper: mapper,
    connectivity: connectivity,
    notifier: notifier,
  );
  ref.onDispose(service.dispose);
  return service;
});

class SyncService {
  SyncService({
    required AppDatabase db,
    required ISyncRepository repo,
    required SyncMapper mapper,
    required ConnectivityMonitor connectivity,
    required SyncStateNotifier notifier,
  })  : _db = db,
        _repo = repo,
        _mapper = mapper,
        _connectivity = connectivity,
        _notifier = notifier;

  final AppDatabase _db;
  final ISyncRepository _repo;
  final SyncMapper _mapper;
  final ConnectivityMonitor _connectivity;
  final SyncStateNotifier _notifier;

  StreamSubscription<bool>? _connectivitySub;
  Timer? _syncTimer;

  void start() {
    _connectivitySub ??= _connectivity.onConnected.listen((_) {
      sync();
    });
    _syncTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (_connectivity.isConnected) {
        sync();
      }
    });
  }

  void dispose() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  Future<void> sync() async {
    if (!_connectivity.isConnected) {
      _notifier.markOffline();
      return;
    }
    _notifier.markSyncing();
    try {
      await push();
      await pull();
      final syncedAt = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kLastSyncedAtPref,
        syncedAt.toUtc().toIso8601String(),
      );
      _notifier.markSynced(syncedAt);
    } catch (e) {
      _notifier.markError(e.toString());
    }
  }

  Future<void> push() async {
    final notes = await _db.notesDao.getDirtyNotes();
    final tasks = await _db.tasksDao.getDirtyTasks();
    final contexts = await _db.contextsDao.getDirtyContexts();
    final tags = await _db.tagsDao.getDirtyTags();
    final completions = await _db.taskCompletionsDao.getDirtyCompletions();

    if (notes.isEmpty &&
        tasks.isEmpty &&
        contexts.isEmpty &&
        tags.isEmpty &&
        completions.isEmpty) {
      return;
    }

    final payload = <String, dynamic>{
      'notes': notes.map(_mapper.noteToJson).toList(),
      'tasks': tasks.map(_mapper.taskToJson).toList(),
      'contexts': contexts.map(_mapper.contextToJson).toList(),
      'tags': tags.map(_mapper.tagToJson).toList(),
      'task_completions':
          completions.map(_mapper.taskCompletionToJson).toList(),
    };

    await _repo.push(payload);

    await _db.transaction(() async {
      for (final n in notes) {
        await _db.notesDao.markHasRemoteCopy(n.id);
        await _db.notesDao.clearDirtyFlag(n.id);
      }
      for (final tsk in tasks) {
        await _db.tasksDao.clearDirtyFlag(tsk.id);
      }
      for (final c in contexts) {
        await _db.contextsDao.clearDirtyFlag(c.id);
      }
      for (final tg in tags) {
        await _db.tagsDao.clearDirtyFlag(tg.id);
      }
      for (final cmp in completions) {
        await _db.taskCompletionsDao.clearDirtyFlag(cmp.id);
      }
    });
  }

  Future<void> pull() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncedStr = prefs.getString(_kLastSyncedAtPref);
    final lastSyncedAt = lastSyncedStr != null
        ? DateTime.parse(lastSyncedStr)
        : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    final data = await _repo.pull(
      lastSyncedAt: lastSyncedAt.toUtc().toIso8601String(),
    );

    await _db.transaction(() async {
      for (final raw in (data['notes'] as List? ?? [])) {
        await _db.notesDao
            .upsertFromRemote(_mapper.noteFromJson(raw as Map<String, dynamic>));
      }
      for (final raw in (data['tasks'] as List? ?? [])) {
        await _db.tasksDao
            .upsertFromRemote(_mapper.taskFromJson(raw as Map<String, dynamic>));
      }
      for (final raw in (data['contexts'] as List? ?? [])) {
        await _db.contextsDao
            .upsertFromRemote(_mapper.contextFromJson(raw as Map<String, dynamic>));
      }
      for (final raw in (data['tags'] as List? ?? [])) {
        await _db.tagsDao
            .upsertFromRemote(_mapper.tagFromJson(raw as Map<String, dynamic>));
      }
    });

    await prefs.setString(
      _kLastSyncedAtPref,
      DateTime.now().toUtc().toIso8601String(),
    );
  }
}

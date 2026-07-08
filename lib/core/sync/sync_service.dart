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

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/current_user.dart';
import '../database/database.dart';
import '../di/providers.dart';
import 'connectivity_monitor.dart';
import 'sync_mapper.dart';
import 'sync_repository.dart';
import 'sync_state.dart';
import 'yjs_websocket_client.dart';

/// SharedPreferences key under which the last successful sync
/// timestamp is persisted across app launches.
const String _kLastSyncedAtPref = 'last_synced_at';

final syncServiceProvider = Provider<SyncService?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;

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
    userId: userId,
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
    required String userId,
  }) : _db = db,
       _repo = repo,
       _mapper = mapper,
       _connectivity = connectivity,
       _notifier = notifier,
       _userId = userId;

  final AppDatabase _db;
  final ISyncRepository _repo;
  final SyncMapper _mapper;
  final ConnectivityMonitor _connectivity;
  final SyncStateNotifier _notifier;
  final String _userId;

  YjsWebSocketClient? _yjsWsClient;
  String? _activeNoteId;

  bool _isSyncing = false;

  StreamSubscription<bool>? _connectivitySub;
  Timer? _syncTimer;

  /// Register the WebSocket client for real-time Yjs sync.
  void setWebSocketClient(YjsWebSocketClient client) {
    _yjsWsClient = client;
  }

  /// Connect real-time sync for [noteId] when it becomes active.
  Future<void> connectNote(String noteId) async {
    _activeNoteId = noteId;
    await _yjsWsClient?.connect(noteId);
  }

  /// Disconnect real-time sync for the active note.
  Future<void> disconnectNote() async {
    if (_activeNoteId != null && kDebugMode) {
      debugPrint('[SyncService] Disconnecting note=$_activeNoteId');
    }
    _activeNoteId = null;
    await _yjsWsClient?.disconnect();
  }

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
    _yjsWsClient?.dispose();
    _yjsWsClient = null;
  }

  Future<void> sync() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      if (!_connectivity.isConnected) {
        _notifier.markOffline();
        return;
      }
      _notifier.markSyncing();
      await push();
      await pull();
      final syncedAt = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kLastSyncedAtPref,
        syncedAt.toUtc().toIso8601String(),
      );
      _notifier.markSynced(syncedAt);
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[SyncService] Error: $e\n$stackTrace');
      }
      _notifier.markError(e.toString());
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> push() async {
    final notes = await _db.notesDao.getDirtyNotes();
    final pushingNoteIds = notes.map((n) => n.id).toSet();
    final remoteNotes = await (_db.select(_db.notes)..where((t) => t.hasRemoteCopy.equals(true))).get();
    final remoteNoteIds = remoteNotes.map((n) => n.id).toSet();
    final allowedNoteIds = {...pushingNoteIds, ...remoteNoteIds};

    final noteNodes = await (_db.select(
      _db.noteNodes,
    )..where((t) => t.isDirty.equals(true))).get();
    final filteredNoteNodes = noteNodes.where((nn) => allowedNoteIds.contains(nn.noteId)).toList();

    final tasks = await _db.tasksDao.getDirtyTasks();
    final filteredTasks = tasks.where((t) => allowedNoteIds.contains(t.noteId)).toList();

    final completions = await _db.taskCompletionsDao.getDirtyCompletions();
    final List<LocalTaskCompletionData> filteredCompletions;
    if (completions.isEmpty) {
      filteredCompletions = [];
    } else {
      final dirtyTaskIds = completions.map((c) => c.taskId).toSet();
      final tasksForCompletions = await (_db.select(_db.tasks)..where((t) => t.id.isIn(dirtyTaskIds))).get();
      final taskIdToNoteId = {for (final t in tasksForCompletions) t.id: t.noteId};
      filteredCompletions = completions.where((c) {
        final noteId = taskIdToNoteId[c.taskId];
        return noteId != null && allowedNoteIds.contains(noteId);
      }).toList();
    }

    final noteLinks = await _db.noteLinksDao.getDirtyLinks();
    final filteredLinks = noteLinks.where((l) => allowedNoteIds.contains(l.sourceId) && allowedNoteIds.contains(l.targetId)).toList();

    final noteTags = await _db.noteTagsDao.getDirtyNoteTags();
    final filteredNoteTags = noteTags.where((nt) => allowedNoteIds.contains(nt.noteId)).toList();

    final prefs = await _db.userNotePreferencesDao.getDirtyPreferences();
    final filteredPrefs = prefs.where((p) => allowedNoteIds.contains(p.noteId)).toList();

    final contexts = await _db.contextsDao.getDirtyContexts();
    final tags = await _db.tagsDao.getDirtyTags();

    if (notes.isEmpty &&
        filteredNoteNodes.isEmpty &&
        filteredTasks.isEmpty &&
        contexts.isEmpty &&
        tags.isEmpty &&
        filteredCompletions.isEmpty &&
        filteredLinks.isEmpty &&
        filteredNoteTags.isEmpty &&
        filteredPrefs.isEmpty) {
      return;
    }

    final payload = <String, dynamic>{
      'notes': notes.map(_mapper.noteToJson).toList(),
      'note_nodes': filteredNoteNodes.map(_mapper.noteNodeToJson).toList(),
      'tasks': filteredTasks.map(_mapper.taskToJson).toList(),
      'contexts': contexts.map(_mapper.contextToJson).toList(),
      'tags': tags.map(_mapper.tagToJson).toList(),
      'task_completions': filteredCompletions
          .map(_mapper.taskCompletionToJson)
          .toList(),
      'note_links': filteredLinks.map(_mapper.noteLinkToJson).toList(),
      'note_tags': filteredNoteTags.map(_mapper.localNoteTagToJson).toList(),
      'user_note_preferences': filteredPrefs
          .map(_mapper.userNotePreferenceToJson)
          .toList(),
    };

    await _repo.push(payload);

    await _db.transaction(() async {
      for (final n in notes) {
        await _db.notesDao.markHasRemoteCopy(n.id);
        await _db.notesDao.clearDirtyFlag(n.id, n.updatedAt);
      }
      await _db.batch((batch) {
        for (final nn in filteredNoteNodes) {
          batch.update(
            _db.noteNodes,
            const NoteNodesCompanion(isDirty: Value(false)),
            where: (t) => t.id.equals(nn.id) & t.updatedAt.equals(nn.updatedAt),
          );
        }
      });
      for (final tsk in filteredTasks) {
        await _db.tasksDao.clearDirtyFlag(tsk.id, tsk.updatedAt);
      }
      for (final c in contexts) {
        await _db.contextsDao.clearDirtyFlag(c.id, c.updatedAt);
      }
      for (final tg in tags) {
        await _db.tagsDao.clearDirtyFlag(tg.id, tg.updatedAt);
      }
      for (final cmp in filteredCompletions) {
        await _db.taskCompletionsDao.clearDirtyFlag(cmp.id);
      }
      for (final nl in filteredLinks) {
        await _db.noteLinksDao.clearDirtyFlag(nl.id, nl.updatedAt);
      }
      for (final nt in filteredNoteTags) {
        await _db.noteTagsDao.clearDirtyFlag(nt.noteId, nt.tagId);
      }
      for (final p in filteredPrefs) {
        await _db.userNotePreferencesDao.clearDirtyFlag(p.userId, p.noteId);
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
    final dirtyNoteIds = {
      for (final note in await (_db.select(
        _db.notes,
      )..where((t) => t.isDirty.equals(true))).get())
        note.id,
    };

    await _db.batch((batch) {
      for (final raw in (data['notes'] as List? ?? [])) {
        final note = _mapper
            .noteFromJson(raw as Map<String, dynamic>)
            .copyWith(isDirty: false, hasRemoteCopy: true);
        if (dirtyNoteIds.contains(note.id)) {
          continue;
        }
        batch.insert(_db.notes, note, onConflict: DoUpdate((_) => note));
      }
      for (final raw in (data['note_nodes'] as List? ?? [])) {
        final node = _mapper
            .noteNodeFromJson(raw as Map<String, dynamic>)
            .copyWith(isDirty: false);
        batch.insert(_db.noteNodes, node, onConflict: DoUpdate((_) => node));
      }
      for (final raw in (data['tasks'] as List? ?? [])) {
        final task = _mapper
            .taskFromJson(raw as Map<String, dynamic>)
            .copyWith(isDirty: false);
        batch.insert(_db.tasks, task, onConflict: DoUpdate((_) => task));
      }
      for (final raw in (data['contexts'] as List? ?? [])) {
        final context = _mapper
            .contextFromJson(raw as Map<String, dynamic>)
            .copyWith(isDirty: false);
        batch.insert(
          _db.contexts,
          context,
          onConflict: DoUpdate((_) => context),
        );
      }
      for (final raw in (data['tags'] as List? ?? [])) {
        final tag = _mapper
            .tagFromJson(raw as Map<String, dynamic>)
            .copyWith(isDirty: false);
        batch.insert(_db.tags, tag, onConflict: DoUpdate((_) => tag));
      }
      for (final raw in (data['task_completions'] as List? ?? [])) {
        final completion = _mapper
            .taskCompletionFromJson(
              raw as Map<String, dynamic>,
              userId: _userId,
            )
            .copyWith(isDirty: false);
        batch.insert(
          _db.localTaskCompletions,
          completion,
          onConflict: DoUpdate((_) => completion),
        );
      }
      for (final raw in (data['note_links'] as List? ?? [])) {
        final link = _mapper
            .noteLinkFromJson(raw as Map<String, dynamic>)
            .copyWith(isDirty: false);
        batch.insert(_db.noteLinks, link, onConflict: DoUpdate((_) => link));
      }
      for (final raw in (data['note_tags'] as List? ?? [])) {
        final noteTag = _mapper
            .localNoteTagFromJson(raw as Map<String, dynamic>)
            .copyWith(isDirty: false);
        batch.insert(
          _db.localNoteTags,
          noteTag,
          onConflict: DoUpdate((_) => noteTag),
        );
      }
      for (final raw in (data['user_note_preferences'] as List? ?? [])) {
        final pref = _mapper.userNotePreferenceFromJson(
          raw as Map<String, dynamic>,
        );
        batch.insert(
          _db.userNotePreferences,
          pref,
          onConflict: DoUpdate((_) => pref),
        );
      }
    });

    await prefs.setString(
      _kLastSyncedAtPref,
      DateTime.now().toUtc().toIso8601String(),
    );
  }
}

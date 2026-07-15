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
import 'package:web_socket_channel/io.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/constants/api_constants.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';

import 'connectivity_monitor.dart';
import 'sync_mapper.dart';
import 'sync_state.dart';
import 'yjs_sync_manager.dart';
import 'yjs_websocket_client.dart';

/// SharedPreferences key under which the last successful sync
/// timestamp is persisted across app launches.
const String _kLastSyncedAtPref = 'last_synced_at';

final syncServiceProvider = Provider<SyncService?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;

  final db = ref.watch(appDatabaseProvider);
  final connectivity = ref.watch(connectivityMonitorProvider);
  final notifier = ref.watch(syncStateProvider.notifier);
  final yjsMgr = ref.watch(yjsSyncManagerProvider);
  final authStorage = ref.watch(authLocalStorageProvider);

  final mapper = SyncMapper();

  final service = SyncService(
    db: db,
    apiClient: ref.watch(apiClientProvider),
    mapper: mapper,
    connectivity: connectivity,
    notifier: notifier,
    yjsMgr: yjsMgr,
    authStorage: authStorage,
  );
  ref.onDispose(service.dispose);
  return service;
});

class SyncService {
  SyncService({
    required AppDatabase db,
    required ApiClient apiClient,
    required SyncMapper mapper,
    required ConnectivityMonitor connectivity,
    required SyncStateNotifier notifier,
    required YjsSyncManager yjsMgr,
    required AuthLocalStorage authStorage,
  }) : _db = db,
       _api = apiClient,
       _mapper = mapper,
       _connectivity = connectivity,
       _notifier = notifier,
       _yjsMgr = yjsMgr,
       _authStorage = authStorage;

  final AppDatabase _db;
  final ApiClient _api;
  final SyncMapper _mapper;
  final ConnectivityMonitor _connectivity;
  final SyncStateNotifier _notifier;
  final YjsSyncManager _yjsMgr;
  final AuthLocalStorage _authStorage;

  YjsWebSocketClient? _yjsWsClient;
  String? _activeNoteId;
  StreamSubscription<Uint8List>? _yjsUpdateSub;
  Timer? _persistDebounce;

  bool _isSyncing = false;

  /// Tracks last successful push time per note Yjs state so we only push
  /// states that changed since then.
  final Map<String, DateTime> _lastYjsSyncAt = {};

  StreamSubscription<bool>? _connectivitySub;
  Timer? _syncTimer;

  /// Checks if a note is currently open and managed by the real-time WebSocket connection.
  /// If true, we should skip REST sync (push/pull) for its YDoc state to avoid races.
  bool isNoteUnderActiveWsManagement(String noteId) {
    return _activeNoteId != null && _activeNoteId == noteId;
  }

  /// Connect real-time Yjs sync for [noteId] when it becomes active.
  Future<void> connectNote(
    String noteId, {
    void Function(Doc doc, void Function(Uint8List) sendUpdate)? onReady,
  }) async {
    final sw = Stopwatch()..start();
    debugPrint('[SyncService] connectNote START noteId=$noteId currentActive=$_activeNoteId');
    if (noteId == _activeNoteId && _yjsWsClient != null) {
      debugPrint('[SyncService] connectNote SKIP (already active) elapsed=${sw.elapsedMilliseconds}ms');
      return;
    }
    await disconnectNote();
    debugPrint('[SyncService] connectNote disconnected previous elapsed=${sw.elapsedMilliseconds}ms');
    final accessToken = await _authStorage.getAccessToken();
    if (accessToken == null) {
      debugPrint('[SyncService] connectNote FAIL: no access token elapsed=${sw.elapsedMilliseconds}ms');
      _notifier.markError('Access token is missing');
      return;
    }
    try {
      _activeNoteId = noteId;
      final noteData = await _db.notesDao.getNoteById(noteId);
      if (noteData != null && !noteData.hasRemoteCopy) {
        debugPrint('[SyncService] connectNote: note missing on server, pushing first...');
        await push();
      }
      debugPrint('[SyncService] connectNote loading doc elapsed=${sw.elapsedMilliseconds}ms');
      final doc = await _yjsMgr.loadDoc(noteId);
      debugPrint('[SyncService] connectNote doc loaded elapsed=${sw.elapsedMilliseconds}ms');
      String wsUrl = ApiConstants.baseUrl
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://');
      if (wsUrl.endsWith('/api/v1')) {
        wsUrl = '$wsUrl/sync/ws/$noteId';
      } else {
        wsUrl = '$wsUrl/api/v1/sync/ws/$noteId';
      }
      final uri = Uri.parse(wsUrl);
      debugPrint('[SyncService] connectNote connecting WS url=$wsUrl elapsed=${sw.elapsedMilliseconds}ms');
      _yjsWsClient = YjsWebSocketClient(
        channelBuilder: () async {
          final token = await _authStorage.getAccessToken();
          if (token == null) throw Exception('No access token');
          // IOWebSocketChannel.connect() ignores custom headers on Android/iOS,
          // so we pass the token as a query param instead.
          final uriWithToken = uri.replace(
            queryParameters: {'token': token},
          );
          return IOWebSocketChannel.connect(uriWithToken);
        },
        doc: doc,
        notifier: _notifier,
        onIdleDisconnect: () {
          _activeNoteId = null;
          _lastYjsSyncAt.clear();
          debugPrint('[SyncService] WS idle disconnect for noteId=$noteId');
        },
      );
      debugPrint('[SyncService] connectNote calling WS connect elapsed=${sw.elapsedMilliseconds}ms');
      await _yjsWsClient!.connect(noteId);
      debugPrint('[SyncService] connectNote WS connected elapsed=${sw.elapsedMilliseconds}ms');
      _yjsUpdateSub = _yjsWsClient!.onUpdate.listen(_handleIncomingUpdate);
      onReady?.call(doc, (update) => _yjsWsClient?.sendUpdate(update));
      debugPrint('[SyncService] connectNote DONE elapsed=${sw.elapsedMilliseconds}ms');
    } catch (e, stackTrace) {
      debugPrint('[SyncService] connectNote FAIL: $e\n$stackTrace');
      _notifier.markError(e.toString());
      rethrow;
    }
  }

  void _handleIncomingUpdate(Uint8List _) {
    final noteId = _activeNoteId;
    if (noteId == null) return;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 500), () {
      _yjsMgr.persist(noteId);
    });
  }

  /// Disconnect real-time sync for the active note.
  Future<void> disconnectNote() async {
    final sw = Stopwatch()..start();
    debugPrint('[SyncService] disconnectNote START noteId=$_activeNoteId');
    final noteId = _activeNoteId;
    if (noteId != null) {
      await _yjsMgr.persist(noteId);
    }
    await _yjsUpdateSub?.cancel();
    _yjsUpdateSub = null;
    _activeNoteId = null;
    if (_yjsWsClient != null) {
      await _yjsWsClient!.disconnect();
      await _yjsWsClient!.dispose();
      _yjsWsClient = null;
    }
    debugPrint('[SyncService] disconnectNote DONE elapsed=${sw.elapsedMilliseconds}ms');
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
    _persistDebounce?.cancel();
    _persistDebounce = null;
    _yjsUpdateSub?.cancel();
    _yjsUpdateSub = null;
    _yjsWsClient?.dispose();
    _yjsWsClient = null;
  }

  Future<void> sync() async {
    if (_isSyncing) {
      debugPrint('[SyncService] sync SKIP (already syncing)');
      return;
    }
    final sw = Stopwatch()..start();
    _isSyncing = true;
    debugPrint('[SyncService] sync START');
    try {
      if (!_connectivity.isConnected) {
        debugPrint('[SyncService] sync: offline, skipping');
        _notifier.markOffline();
        return;
      }
      _notifier.markSyncing();
      debugPrint('[SyncService] sync: push START');
      await push();
      debugPrint('[SyncService] sync: push DONE, pull START elapsed=${sw.elapsedMilliseconds}ms');
      await pull();
      debugPrint('[SyncService] sync: pull DONE elapsed=${sw.elapsedMilliseconds}ms');
      final syncedAt = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kLastSyncedAtPref,
        syncedAt.toUtc().toIso8601String(),
      );
      _notifier.markSynced(syncedAt);
      debugPrint('[SyncService] sync DONE elapsed=${sw.elapsedMilliseconds}ms');
    } catch (e, stackTrace) {
      debugPrint('[SyncService] sync FAIL: $e\n$stackTrace');
      _notifier.markError(e.toString());
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> push() async {
    final sw = Stopwatch()..start();
    debugPrint('[SyncService] push START');
    final notes = await _db.notesDao.getDirtyNotes();
    final pushingNoteIds = notes.map((n) => n.id).toSet();
    final remoteNotes = await (_db.select(_db.notes)..where((t) => t.hasRemoteCopy.equals(true))).get();
    final remoteNoteIds = remoteNotes.map((n) => n.id).toSet();
    final allowedNoteIds = {...pushingNoteIds, ...remoteNoteIds};

    final noteLinks = await _db.noteLinksDao.getDirtyLinks();
    final filteredLinks = noteLinks.where((l) => allowedNoteIds.contains(l.sourceId) && allowedNoteIds.contains(l.targetId)).toList();

    final noteTags = await _db.noteTagsDao.getDirtyNoteTags();
    final filteredNoteTags = noteTags.where((nt) => allowedNoteIds.contains(nt.noteId)).toList();

    final prefs = await _db.userNotePreferencesDao.getDirtyPreferences();
    final filteredPrefs = prefs.where((p) => allowedNoteIds.contains(p.noteId)).toList();

    final contexts = await _db.contextsDao.getDirtyContexts();
    final tags = await _db.tagsDao.getDirtyTags();

    // Collect dirty Yjs states (skip the currently active note — it syncs via WS).
    final allYjsStates = await (_db.select(_db.localYjsStates)).get();
    final yjsStates = <LocalYjsState>[];
    for (final s in allYjsStates) {
      if (isNoteUnderActiveWsManagement(s.noteId)) continue;
      final lastSync = _lastYjsSyncAt[s.noteId];
      if (lastSync == null || s.updatedAt.isAfter(lastSync)) {
        // Migration: decode and re-encode to strip out buggy formatting
        // from older dart_crdt versions before sending to Go backend.
        try {
          final tmpDoc = Doc();
          applyUpdateSafe(tmpDoc, s.state);
          final cleanState = encodeStateAsUpdate(tmpDoc);
          yjsStates.add(s.copyWith(state: cleanState));
        } catch (e, st) {
          debugPrint('[SyncService] migration failed for noteId=${s.noteId}: $e\n$st');
          // State is hopelessly corrupted. Delete it to prevent endless sync loops
          // and allow it to be pulled fresh from the server next time.
          await (_db.delete(_db.localYjsStates)..where((t) => t.noteId.equals(s.noteId))).go();
        }
      }
    }

    debugPrint('[SyncService] push: dirty data collected elapsed=${sw.elapsedMilliseconds}ms notes=${notes.length} links=${filteredLinks.length} yjsStates=${yjsStates.length}');

    if (notes.isEmpty &&
        contexts.isEmpty &&
        tags.isEmpty &&
        filteredLinks.isEmpty &&
        filteredNoteTags.isEmpty &&
        filteredPrefs.isEmpty &&
        yjsStates.isEmpty) {
      debugPrint('[SyncService] push: nothing dirty, SKIP elapsed=${sw.elapsedMilliseconds}ms');
      return;
    }

    final payload = <String, dynamic>{
      'notes': notes.map(_mapper.noteToJson).toList(),
      'contexts': contexts.map(_mapper.contextToJson).toList(),
      'tags': tags.map(_mapper.tagToJson).toList(),
      'note_links': filteredLinks.map(_mapper.noteLinkToJson).toList(),
      'note_tags': filteredNoteTags.map(_mapper.localNoteTagToJson).toList(),
      'user_note_preferences': filteredPrefs
          .map(_mapper.userNotePreferenceToJson)
          .toList(),
      'note_yjs_states': yjsStates.map(_mapper.localYjsStateToJson).toList(),
    };

    debugPrint('[SyncService] push: sending HTTP POST elapsed=${sw.elapsedMilliseconds}ms');
    await _api.post('/sync/push', data: payload);
    debugPrint('[SyncService] push: HTTP POST done elapsed=${sw.elapsedMilliseconds}ms');

    final now = DateTime.now();
    for (final s in yjsStates) {
      _lastYjsSyncAt[s.noteId] = now;
    }

    debugPrint('[SyncService] push: clearing dirty flags elapsed=${sw.elapsedMilliseconds}ms');
    await _db.transaction(() async {
      for (final n in notes) {
        await _db.notesDao.markHasRemoteCopy(n.id);
        await _db.notesDao.clearDirtyFlag(n.id, n.updatedAt);
      }
      for (final c in contexts) {
        await _db.contextsDao.clearDirtyFlag(c.id, c.updatedAt);
      }
      for (final tg in tags) {
        await _db.tagsDao.clearDirtyFlag(tg.id, tg.updatedAt);
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
    debugPrint('[SyncService] push DONE elapsed=${sw.elapsedMilliseconds}ms');
  }

  Future<void> pull() async {
    final sw = Stopwatch()..start();
    debugPrint('[SyncService] pull START');
    final prefs = await SharedPreferences.getInstance();
    final lastSyncedStr = prefs.getString(_kLastSyncedAtPref);
    final lastSyncedAt = lastSyncedStr != null
        ? DateTime.parse(lastSyncedStr)
        : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    debugPrint('[SyncService] pull: HTTP GET lastSyncedAt=$lastSyncedStr');
    final response = await _api.post<Map<String, dynamic>>(
      '/sync/pull',
      data: {
        'last_synced_at': lastSyncedAt.toUtc().toIso8601String(),
        'limit': 100000,
      },
    );
    final data = response.data ?? const <String, dynamic>{};
    debugPrint('[SyncService] pull: HTTP GET done elapsed=${sw.elapsedMilliseconds}ms');
    final dirtyNoteIds = {
      for (final note in await (_db.select(
        _db.notes,
      )..where((t) => t.isDirty.equals(true))).get())
        note.id,
    };

    debugPrint('[SyncService] pull: applying batch elapsed=${sw.elapsedMilliseconds}ms notes=${(data['notes'] as List?)?.length ?? 0}');
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

    for (final raw in (data['note_yjs_states'] as List? ?? [])) {
      final remoteState = _mapper.localYjsStateFromJson(
        raw as Map<String, dynamic>,
      );
      if (isNoteUnderActiveWsManagement(remoteState.noteId)) {
        debugPrint('[SyncService] pull: skipping note_yjs_state for active note=${remoteState.noteId}');
        continue;
      }

      // Merge: load local, apply remote on top (local wins for concurrent edits)
      final tmpDoc = Doc();
      try {
        final localStateRow = await (_db.select(_db.localYjsStates)
          ..where((t) => t.noteId.equals(remoteState.noteId)))
          .getSingleOrNull();

        if (localStateRow != null) {
          applyUpdateSafe(tmpDoc, localStateRow.state);
        }
        applyUpdateSafe(tmpDoc, remoteState.state);

        final mergedState = encodeStateAsUpdate(tmpDoc);
        await _db.into(_db.localYjsStates).insertOnConflictUpdate(
          LocalYjsStatesCompanion(
            noteId: Value(remoteState.noteId),
            state: Value(mergedState),
            updatedAt: Value(DateTime.now()),
          ),
        );
        _yjsMgr.evictDoc(remoteState.noteId);
      } catch (e, _) {
        debugPrint('[SyncService] pull: merge failed for ${remoteState.noteId}, falling back to remote: $e');
        await _db.into(_db.localYjsStates).insertOnConflictUpdate(
          LocalYjsStatesCompanion(
            noteId: Value(remoteState.noteId),
            state: Value(remoteState.state),
            updatedAt: Value(remoteState.updatedAt),
          ),
        );
      }
    }

    final nextSyncedAtStr = data['synced_at'] as String?;
    if (nextSyncedAtStr != null) {
      await prefs.setString(_kLastSyncedAtPref, nextSyncedAtStr);
    } else {
      await prefs.setString(
        _kLastSyncedAtPref,
        DateTime.now().toUtc().toIso8601String(),
      );
    }
    debugPrint('[SyncService] pull DONE elapsed=${sw.elapsedMilliseconds}ms');
  }
}

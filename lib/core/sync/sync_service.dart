library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/di/providers.dart';

import 'connectivity_monitor.dart';
import 'sync_mapper.dart';
import 'sync_state.dart';
import 'yjs_sync_manager.dart';

const String _kLastSyncedAtPref = 'last_synced_at';

final syncServiceProvider = Provider<SyncService?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;

  final db = ref.watch(appDatabaseProvider);
  final connectivity = ref.watch(connectivityMonitorProvider);
  final notifier = ref.watch(syncStateProvider.notifier);
  final yjsMgr = ref.watch(yjsSyncManagerProvider);

  final mapper = SyncMapper();

  final service = SyncService(
    db: db,
    apiClient: ref.watch(apiClientProvider),
    mapper: mapper,
    connectivity: connectivity,
    notifier: notifier,
    yjsMgr: yjsMgr,
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
  }) : _db = db,
       _api = apiClient,
       _mapper = mapper,
       _connectivity = connectivity,
       _notifier = notifier,
       _yjsMgr = yjsMgr;

  final AppDatabase _db;
  final ApiClient _api;
  final SyncMapper _mapper;
  final ConnectivityMonitor _connectivity;
  final SyncStateNotifier _notifier;
  final YjsSyncManager _yjsMgr;

  String? _activeNoteId;
  Timer? _syncTimer;
  AppLifecycleListener? _lifecycleListener;

  bool _isSyncing = false;

  /// Per-note sync queue to serialize exchanges per note.
  final Map<String, Future<void>> _noteSyncChains = {};

  /// Monotonically increasing generation counter per note so [_syncNote]
  /// can check whether another call has already been chained after it.
  final Map<String, int> _noteSyncGenerations = {};

  /// Set of note IDs that have been locally edited since last exchange.
  /// Avoids encoding, DB query, and HTTP call when nothing changed.
  final Set<String> _dirtyNotes = {};

  /// Monotonically increasing generation counter per note so [_exchangeNote]
  /// can detect concurrent edits during an in-flight HTTP request.
  /// If the generation has changed between the start and end of an exchange,
  /// the dirty flag is NOT cleared — ensuring the new edit is sent.
  final Map<String, int> _dirtyGenerations = {};

  StreamSubscription<bool>? _connectivitySub;
  Timer? _periodicSyncTimer;

  /// Marks a note as having local changes needing sync.
  void markDirty(String noteId) {
    final gen = (_dirtyGenerations[noteId] ?? 0) + 1;
    _dirtyGenerations[noteId] = gen;
    _dirtyNotes.add(noteId);
  }

  Future<Doc?> connectNote(String noteId) async {
    final sw = Stopwatch()..start();
    debugPrint('[SyncService] connectNote START noteId=$noteId currentActive=$_activeNoteId');
    if (noteId == _activeNoteId && _syncTimer != null) {
      debugPrint('[SyncService] connectNote SKIP (already active) elapsed=${sw.elapsedMilliseconds}ms');
      return null;
    }
    await disconnectNote();
    debugPrint('[SyncService] connectNote disconnected previous elapsed=${sw.elapsedMilliseconds}ms');

    try {
      final noteData = await _db.notesDao.getNoteById(noteId);
      if (noteData != null && !noteData.hasRemoteCopy) {
        debugPrint('[SyncService] connectNote: note missing on server, scheduling push...');
        unawaited(push());
      }

      _activeNoteId = noteId;
      debugPrint('[SyncService] connectNote loading doc elapsed=${sw.elapsedMilliseconds}ms');
      final doc = await _yjsMgr.loadDoc(noteId);
      debugPrint('[SyncService] connectNote doc loaded elapsed=${sw.elapsedMilliseconds}ms');

      void startTimer() {
        _syncTimer?.cancel();
        _syncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
          if (_dirtyNotes.contains(noteId)) {
            unawaited(syncDirtyNote(noteId));
          }
        });
      }

      void stopTimer() {
        _syncTimer?.cancel();
        _syncTimer = null;
      }

      markDirty(noteId);
      startTimer();
      debugPrint('[SyncService] connectNote polling timer started elapsed=${sw.elapsedMilliseconds}ms');

      // Register lifecycle listener for app pause/inactive/resume
      _lifecycleListener = AppLifecycleListener(
        onPause: () {
          debugPrint('[SyncService] lifecycle: onPause — triggering sync and stopping timer');
          markDirty(noteId);
          unawaited(syncDirtyNote(noteId));
          stopTimer();
        },
        onInactive: () {
          debugPrint('[SyncService] lifecycle: onInactive — triggering sync and stopping timer');
          markDirty(noteId);
          unawaited(syncDirtyNote(noteId));
          stopTimer();
        },
        onResume: () {
          debugPrint('[SyncService] lifecycle: onResume — restarting timer');
          markDirty(noteId);
          startTimer();
          unawaited(syncDirtyNote(noteId));
        },
      );

      debugPrint('[SyncService] connectNote DONE elapsed=${sw.elapsedMilliseconds}ms');
      return doc;
    } catch (e, stackTrace) {
      debugPrint('[SyncService] connectNote FAIL: $e\n$stackTrace');
      _notifier.markError(e.toString());
      rethrow;
    }
  }

  Future<void> disconnectNote() async {
    final sw = Stopwatch()..start();
    debugPrint('[SyncService] disconnectNote START noteId=$_activeNoteId');
    final noteId = _activeNoteId;

    _syncTimer?.cancel();
    _syncTimer = null;
    _lifecycleListener?.dispose();
    _lifecycleListener = null;

    try {
      if (noteId != null && _dirtyNotes.contains(noteId)) {
        await syncDirtyNote(noteId);
      }
    } finally {
      if (noteId != null) {
        await _yjsMgr.persist(noteId);
      }
      _activeNoteId = null;
    }

    debugPrint('[SyncService] disconnectNote DONE elapsed=${sw.elapsedMilliseconds}ms');
  }

  /// Per-note Yjs delta exchange.
  ///
  /// Serializes exchanges for the same note via a generation-counter chain so
  /// concurrent calls are queued sequentially.  Errors are propagated to the
  /// caller but do NOT poison the chain for subsequent calls.
  ///
  /// This is the ONE exchange method — both the active-note polling timer and
  /// background batch push use it.
  Future<void> syncDirtyNote(String noteId) {
    final gen = (_noteSyncGenerations[noteId] ?? 0) + 1;
    _noteSyncGenerations[noteId] = gen;

    if (!_noteSyncChains.containsKey(noteId)) {
      _noteSyncChains[noteId] = Future.value();
    }

    // inner: carries the real result/error back to the caller
    final inner = _noteSyncChains[noteId]!.then((_) async {
      try {
        await _exchangeNote(noteId);
      } finally {
        if (_noteSyncGenerations[noteId] == gen) {
          _noteSyncChains.remove(noteId);
          _noteSyncGenerations.remove(noteId);
        }
      }
    });

    // Chain entry swallows errors so a failing exchange never blocks
    // subsequent calls for the same note.
    _noteSyncChains[noteId] = inner.catchError((_) {});

    return inner;
  }

  Future<void> _exchangeNote(String noteId) async {
    if (!_dirtyNotes.contains(noteId)) return;
    final genAtStart = _dirtyGenerations[noteId] ?? 0;

    final doc = await _yjsMgr.loadDoc(noteId);
    final localState = await _getLocalState(noteId);
    final sv = localState?.syncedStateVector;

    final localUpdate = encodeStateAsUpdate(doc, sv);
    if (localUpdate.isEmpty) {
      _tryClearDirty(noteId, genAtStart);
      return;
    }

    final stateVector = encodeStateVector(doc);
    final svB64 = base64Encode(stateVector);

    debugPrint('[SyncService] _exchangeNote: sending ${localUpdate.length}B for note $noteId');

    final response = await _api.post<List<int>>(
      '/sync/note/$noteId',
      data: Stream.fromIterable([localUpdate]),
      options: Options(
        headers: {
          'X-State-Vector': svB64,
        },
        contentType: 'application/octet-stream',
        responseType: ResponseType.bytes,
      ),
    );

    final responseData = response.data;
    if (responseData != null && responseData.isNotEmpty) {
      final serverUpdate = Uint8List.fromList(responseData);
      applyUpdate(doc, serverUpdate);
      debugPrint('[SyncService] _exchangeNote: applied ${serverUpdate.length}B from server for note $noteId');
    }

    // Persist state always. Only advance synced state vector if no concurrent
    // edit happened during the HTTP request — if generation changed, keeping
    // the old SV ensures the next exchange computes a delta that includes it.
    if (_dirtyGenerations[noteId] == genAtStart) {
      await _yjsMgr.persistWithSyncedVector(noteId, encodeStateVector(doc));
      // Re-check after the async persist — a concurrent edit during the
      // database write would have bumped the generation.
      if (_dirtyGenerations[noteId] == genAtStart) {
        // Clear while the generation is still present. Removing it first
        // makes the ownership check fail and leaves this note dirty forever.
        _tryClearDirty(noteId, genAtStart);
        _dirtyGenerations.remove(noteId);
      }
    } else {
      await _yjsMgr.persist(noteId);
    }

    // Project remote changes to SQLite so list views reflect the update
    // even for background notes (not just the active editor).
    if (_activeNoteId != noteId) {
      await _yjsMgr.projectNodes(noteId, markDirty: false);
    }
  }

  /// Clears the dirty flag for [noteId] only if no new edit happened
  /// during the exchange (i.e., the generation hasn't changed).
  /// Keeps the generation entry for the SV check that follows.
  void _tryClearDirty(String noteId, int genAtStart) {
    if (_dirtyGenerations[noteId] == genAtStart) {
      _dirtyNotes.remove(noteId);
    }
  }

  Future<LocalYjsState?> _getLocalState(String noteId) async {
    final states = await (_db.select(_db.localYjsStates)
      ..where((t) => t.noteId.equals(noteId))).get();
    return states.isNotEmpty ? states.first : null;
  }

  void start() {
    _connectivitySub ??= _connectivity.onConnected.listen((_) {
      sync();
    });
    _periodicSyncTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (_connectivity.isConnected) {
        sync();
      }
    });
  }

  void dispose() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _syncTimer?.cancel();
    _syncTimer = null;
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
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
      final prefs = await SharedPreferences.getInstance();
      final lastSyncedStr = prefs.getString(_kLastSyncedAtPref);
      final syncedAt = lastSyncedStr != null ? DateTime.parse(lastSyncedStr) : DateTime.now();
      _notifier.markSynced(syncedAt);
      debugPrint('[SyncService] sync DONE elapsed=${sw.elapsedMilliseconds}ms');
    } catch (e, stackTrace) {
      debugPrint('[SyncService] sync FAIL: $e\n$stackTrace');
      if (e is DioException && e.response?.statusCode == 409) {
        final data = e.response?.data;
        if (data is Map && data['error'] == 'NOTE_DELETED') {
          _notifier.markError('Aviso: Uma nota sendo editada foi deletada remotamente. Salve uma cópia local se necessário.');
          return;
        }
      }
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

    debugPrint('[SyncService] push: dirty data collected elapsed=${sw.elapsedMilliseconds}ms notes=${notes.length} links=${filteredLinks.length}');

    if (notes.isEmpty &&
        contexts.isEmpty &&
        tags.isEmpty &&
        filteredLinks.isEmpty &&
        filteredNoteTags.isEmpty &&
        filteredPrefs.isEmpty) {
      debugPrint('[SyncService] push: nothing dirty, SKIP elapsed=${sw.elapsedMilliseconds}ms');
      return;
    }

    // Relational push — no Yjs states. Those are sent separately via
    // per-note delta exchange (syncDirtyNote).
    final payload = <String, dynamic>{
      'notes': notes.map(_mapper.noteToJson).toList(),
      'contexts': contexts.map(_mapper.contextToJson).toList(),
      'tags': tags.map(_mapper.tagToJson).toList(),
      'note_links': filteredLinks.map(_mapper.noteLinkToJson).toList(),
      'note_tags': filteredNoteTags.map(_mapper.localNoteTagToJson).toList(),
      'user_note_preferences': filteredPrefs
          .map(_mapper.userNotePreferenceToJson)
          .toList(),
    };

    debugPrint('[SyncService] push: sending HTTP POST elapsed=${sw.elapsedMilliseconds}ms');
    await _api.post('/sync/push', data: payload);
    debugPrint('[SyncService] push: HTTP POST done elapsed=${sw.elapsedMilliseconds}ms');

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

    // After the relational push, send Yjs deltas for dirty notes (chunked
    // into groups of 2 to avoid overwhelming the network on large batches).
    // Mark them dirty first so the per-note exchange actually runs.
    if (pushingNoteIds.isNotEmpty) {
      debugPrint('[SyncService] push: sending Yjs deltas for ${pushingNoteIds.length} notes');
      for (final id in pushingNoteIds) {
        markDirty(id);
      }
      final ids = pushingNoteIds.toList();
      for (var i = 0; i < ids.length; i += 2) {
        final chunk = ids.skip(i).take(2).toList();
        await Future.wait(chunk.map(syncDirtyNote));
      }
      debugPrint('[SyncService] push: Yjs deltas done elapsed=${sw.elapsedMilliseconds}ms');
    }

    debugPrint('[SyncService] push DONE elapsed=${sw.elapsedMilliseconds}ms');
  }

  Future<void> pull() async {
    final sw = Stopwatch()..start();
    debugPrint('[SyncService] pull START');
    final prefs = await SharedPreferences.getInstance();

    final dirtyNoteIds = {
      for (final note in await (_db.select(
        _db.notes,
      )..where((t) => t.isDirty.equals(true))).get())
        note.id,
    };

    const int pageLimit = 500;
    String? cursor;
    int totalNotes = 0;
    final allRawYjsStates = <Map<String, dynamic>>[];

    while (true) {
      final lastSyncedStr = prefs.getString(_kLastSyncedAtPref);
      final lastSyncedAt = lastSyncedStr != null
          ? DateTime.parse(lastSyncedStr)
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

      debugPrint('[SyncService] pull: HTTP GET lastSyncedAt=$lastSyncedStr cursor=$cursor');
      final response = await _api.post<Map<String, dynamic>>(
        '/sync/pull',
        data: {
          'last_synced_at': cursor ?? lastSyncedAt.toUtc().toIso8601String(),
          'limit': pageLimit,
        },
      );
      final data = response.data ?? const <String, dynamic>{};

      final notes = data['notes'] as List? ?? [];
      if (notes.isEmpty) break;

      totalNotes += notes.length;

      // Collect existing local content for pulled notes so we don't
      // overwrite non-empty local content with a stale/empty server payload.
      final pulledNoteIds = notes
          .map((raw) => (raw as Map<String, dynamic>)['id'] as String)
          .toSet();
      final localContentById = <String, String>{};
      if (pulledNoteIds.isNotEmpty) {
        final rows = await (_db.select(_db.notes)
              ..where((t) => t.id.isIn(pulledNoteIds.toList())))
            .get();
        for (final row in rows) {
          if (row.content.trim().isNotEmpty) {
            localContentById[row.id] = row.content;
          }
        }
      }

      debugPrint('[SyncService] pull: applying page batch elapsed=${sw.elapsedMilliseconds}ms notes=${notes.length}');
      await _db.batch((batch) {
        for (final raw in notes) {
          final json = raw as Map<String, dynamic>;
          final noteId = json['id'] as String;

          if (localContentById.containsKey(noteId)) {
            json['content'] = localContentById[noteId];
          }

          final note = _mapper
              .noteFromJson(json)
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

      // Collect Yjs states from this page
      final pageYjsStates = data['note_yjs_states'] as List? ?? [];
      allRawYjsStates.addAll(pageYjsStates.cast<Map<String, dynamic>>());

      // Update cursor for next page
      cursor = data['synced_at'] as String?;

      if (notes.length < pageLimit) break;
    }

    // Process accumulated Yjs states once after all pages
    if (allRawYjsStates.isNotEmpty) {
      await _yjsMgr.mergeRemoteStatesAndProject(
        rawYjsStates: allRawYjsStates,
        isActiveNote: (noteId) => _activeNoteId != null && _activeNoteId == noteId,
        onMerged: (_) {},
      );
    }

    // Save the final cursor or fall back to now
    if (cursor != null) {
      await prefs.setString(_kLastSyncedAtPref, cursor);
    }
    debugPrint('[SyncService] pull DONE elapsed=${sw.elapsedMilliseconds}ms totalNotes=$totalNotes pages=${totalNotes ~/ pageLimit + (totalNotes % pageLimit != 0 ? 1 : 0)}');
  }
}


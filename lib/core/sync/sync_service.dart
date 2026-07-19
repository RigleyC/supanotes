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

  StreamSubscription<bool>? _connectivitySub;
  Timer? _periodicSyncTimer;

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
        debugPrint('[SyncService] connectNote: note missing on server, pushing first...');
        await push();
      }

      _activeNoteId = noteId;
      debugPrint('[SyncService] connectNote loading doc elapsed=${sw.elapsedMilliseconds}ms');
      final doc = await _yjsMgr.loadDoc(noteId);
      debugPrint('[SyncService] connectNote doc loaded elapsed=${sw.elapsedMilliseconds}ms');

      void startTimer() {
        _syncTimer?.cancel();
        _syncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
          unawaited(syncDirtyNote(noteId));
        });
      }

      void stopTimer() {
        _syncTimer?.cancel();
        _syncTimer = null;
      }

      startTimer();
      debugPrint('[SyncService] connectNote polling timer started elapsed=${sw.elapsedMilliseconds}ms');

      // Register lifecycle listener for app pause/inactive/resume
      _lifecycleListener = AppLifecycleListener(
        onPause: () {
          debugPrint('[SyncService] lifecycle: onPause — triggering sync and stopping timer');
          unawaited(syncDirtyNote(noteId));
          stopTimer();
        },
        onInactive: () {
          debugPrint('[SyncService] lifecycle: onInactive — triggering sync and stopping timer');
          unawaited(syncDirtyNote(noteId));
          stopTimer();
        },
        onResume: () {
          debugPrint('[SyncService] lifecycle: onResume — restarting timer');
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

    if (noteId != null) {
      await _yjsMgr.persist(noteId);
    }

    _syncTimer?.cancel();
    _syncTimer = null;
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
    _activeNoteId = null;

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
        await _exchangeNote(noteId, gen);
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

  Future<void> _exchangeNote(String noteId, int generation) async {
    final doc = await _yjsMgr.loadDoc(noteId);
    final localState = await _getLocalState(noteId);
    final sv = localState?.syncedStateVector;

    final localUpdate = encodeStateAsUpdate(doc, sv);
    if (localUpdate.isEmpty) return;

    final stateVector = encodeStateVector(doc);

    debugPrint('[SyncService] _exchangeNote: sending ${localUpdate.length} bytes for note $noteId');

    final response = await _api.post<List<int>>(
      '/sync/note/$noteId',
      data: Stream.fromIterable([localUpdate]),
      options: Options(
        headers: {
          'X-State-Vector': base64Encode(stateVector),
        },
        contentType: 'application/octet-stream',
        responseType: ResponseType.bytes,
      ),
    );

    final responseData = response.data;
    if (responseData != null && responseData.isNotEmpty) {
      final serverUpdate = Uint8List.fromList(responseData);
      applyUpdate(doc, serverUpdate);
      debugPrint('[SyncService] _exchangeNote: applied ${serverUpdate.length} bytes from server for note $noteId');
    }

    // Persist the new synced state vector ONLY after a successful exchange.
    await _yjsMgr.persistWithSyncedVector(noteId, encodeStateVector(doc));

    // Project remote changes to SQLite so list views reflect the update
    // even for background notes (not just the active editor).
    if (_activeNoteId != noteId) {
      await _yjsMgr.projectNodes(noteId, markDirty: false);
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

    // After the relational push, send Yjs deltas for dirty notes (max 2
    // concurrent to avoid overwhelming the network on large batches).
    if (pushingNoteIds.isNotEmpty) {
      debugPrint('[SyncService] push: sending Yjs deltas for ${pushingNoteIds.length} notes');
      final semaphore = Semaphore(2);
      await Future.wait(
        pushingNoteIds.map((noteId) async {
          await semaphore.acquire();
          try {
            await syncDirtyNote(noteId);
          } finally {
            semaphore.release();
          }
        }),
      );
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
          'last_synced_at': lastSyncedAt.toUtc().toIso8601String(),
          'limit': pageLimit,
          if (cursor != null) 'cursor': cursor,
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

/// Simple semaphore for limiting concurrent Yjs delta exchanges.
class Semaphore {
  Semaphore(this._max);
  final int _max;
  int _acquired = 0;
  final _queue = <void Function()>[];

  Future<void> acquire() async {
    if (_acquired < _max) {
      _acquired++;
      return;
    }
    final completer = Completer<void>();
    _queue.add(completer.complete);
    return completer.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0)();
    } else {
      _acquired--;
    }
  }
}

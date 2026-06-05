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

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database.dart';
import '../di/providers.dart';
import 'connectivity_monitor.dart';
import 'sync_state.dart';

/// SharedPreferences key under which the last successful sync
/// timestamp is persisted across app launches.
const String _kLastSyncedAtPref = 'last_synced_at';

final syncServiceProvider = Provider<SyncService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final dio = ref.watch(apiClientProvider).dio;
  final connectivity = ref.watch(connectivityMonitorProvider);
  final notifier = ref.watch(syncStateProvider.notifier);
  final service = SyncService(
    db: db,
    dio: dio,
    connectivity: connectivity,
    notifier: notifier,
  );
  ref.onDispose(service.dispose);
  return service;
});

class SyncService {
  SyncService({
    required AppDatabase db,
    required Dio dio,
    required ConnectivityMonitor connectivity,
    required SyncStateNotifier notifier,
  })  : _db = db,
        _dio = dio,
        _connectivity = connectivity,
        _notifier = notifier;

  final AppDatabase _db;
  final Dio _dio;
  final ConnectivityMonitor _connectivity;
  final SyncStateNotifier _notifier;

  StreamSubscription<bool>? _connectivitySub;
  Timer? _syncTimer;

  /// Wires the connectivity listener and starts the periodic timer.
  ///
  /// Called by the auth listener in `main.dart` on `AuthAuthenticated`.
  /// Idempotent — calling it twice is a no-op so the lifecycle is
  /// resilient to repeated auth state changes.
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

  /// Cancels the periodic timer and the connectivity subscription.
  ///
  /// Called by the auth listener in `main.dart` on
  /// `AuthUnauthenticated`. After [dispose] the service is dormant and
  /// will not perform any network or database I/O.
  void dispose() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  /// Pushes local dirty rows, then pulls remote changes since the last
  /// successful sync. Emits state transitions through the
  /// [SyncStateNotifier] for the UI banner.
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
      'notes': notes.map(_noteToJson).toList(),
      'tasks': tasks.map(_taskToJson).toList(),
      'contexts': contexts.map(_contextToJson).toList(),
      'tags': tags.map(_tagToJson).toList(),
      'task_completions': completions
          .map((c) => {
                'id': c.id,
                'task_id': c.taskId,
                'completed_at': c.completedAt.toUtc().toIso8601String(),
              })
          .toList(),
    };

    await _dio.post('/sync/push', data: payload);

    await _db.transaction(() async {
      for (final n in notes) {
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

    final response = await _dio.post<Map<String, dynamic>>(
      '/sync/pull',
      data: {
        'last_synced_at': lastSyncedAt.toUtc().toIso8601String(),
        'limit': 500,
      },
    );

    final data = response.data ?? const <String, dynamic>{};

    await _db.transaction(() async {
      for (final raw in (data['notes'] as List? ?? [])) {
        final json = raw as Map<String, dynamic>;
        final note = NoteData(
          id: json['id'] as String,
          userId: json['user_id'] as String,
          contextId: json['context_id'] as String?,
          title: json['title'] as String?,
          content: json['content'] as String,
          excerpt: json['excerpt'] as String?,
          isInbox: (json['is_inbox'] as bool?) ?? false,
          favorite: (json['favorite'] as bool?) ?? false,
          archived: (json['archived'] as bool?) ?? false,
          embeddingStatus: json['embedding_status'] as String?,
          createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
          updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
          deletedAt: json['deleted_at'] != null
              ? DateTime.parse(json['deleted_at'] as String).toLocal()
              : null,
          isDirty: false,
        );
        await _db.notesDao.upsertFromRemote(note);
      }
      for (final raw in (data['tasks'] as List? ?? [])) {
        final json = raw as Map<String, dynamic>;
        final task = TaskData(
          id: json['id'] as String,
          userId: json['user_id'] as String,
          noteId: json['note_id'] as String,
          title: json['title'] as String,
          status: json['status'] as String,
          position: (json['position'] as int?) ?? 0,
          recurrence: json['recurrence'] as String?,
          dueDate: json['due_date'] != null
              ? DateTime.parse(json['due_date'] as String).toLocal()
              : null,
          completedAt: json['completed_at'] != null
              ? DateTime.parse(json['completed_at'] as String).toLocal()
              : null,
          createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
          updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
          deletedAt: json['deleted_at'] != null
              ? DateTime.parse(json['deleted_at'] as String).toLocal()
              : null,
          isDirty: false,
        );
        await _db.tasksDao.upsertFromRemote(task);
      }
      for (final raw in (data['contexts'] as List? ?? [])) {
        final json = raw as Map<String, dynamic>;
        final context = ContextData(
          id: json['id'] as String,
          userId: json['user_id'] as String,
          slug: json['slug'] as String,
          name: json['name'] as String,
          createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
          updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
          isDirty: false,
        );
        await _db.contextsDao.upsertFromRemote(context);
      }
      for (final raw in (data['tags'] as List? ?? [])) {
        final json = raw as Map<String, dynamic>;
        final tag = TagData(
          id: json['id'] as String,
          userId: json['user_id'] as String,
          name: json['name'] as String,
          createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
          updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
          isDirty: false,
        );
        await _db.tagsDao.upsertFromRemote(tag);
      }
    });

    await prefs.setString(
      _kLastSyncedAtPref,
      DateTime.now().toUtc().toIso8601String(),
    );
  }
}

Map<String, dynamic> _noteToJson(NoteData n) => {
      'id': n.id,
      'context_id': n.contextId,
      'title': n.title,
      'content': n.content,
      'excerpt': n.excerpt,
      'is_inbox': n.isInbox,
      'favorite': n.favorite,
      'archived': n.archived,
      'embedding_status': n.embeddingStatus,
      'created_at': n.createdAt.toUtc().toIso8601String(),
      'updated_at': n.updatedAt.toUtc().toIso8601String(),
      'deleted_at': n.deletedAt?.toUtc().toIso8601String(),
    };

Map<String, dynamic> _taskToJson(TaskData t) => {
      'id': t.id,
      'note_id': t.noteId,
      'title': t.title,
      'status': t.status,
      'position': t.position,
      'recurrence': t.recurrence,
      'due_date': t.dueDate?.toUtc().toIso8601String(),
      'completed_at': t.completedAt?.toUtc().toIso8601String(),
      'created_at': t.createdAt.toUtc().toIso8601String(),
      'updated_at': t.updatedAt.toUtc().toIso8601String(),
      'deleted_at': t.deletedAt?.toUtc().toIso8601String(),
    };

Map<String, dynamic> _contextToJson(ContextData c) => {
      'id': c.id,
      'slug': c.slug,
      'name': c.name,
      'created_at': c.createdAt.toUtc().toIso8601String(),
      'updated_at': c.updatedAt.toUtc().toIso8601String(),
    };

Map<String, dynamic> _tagToJson(TagData t) => {
      'id': t.id,
      'name': t.name,
      'created_at': t.createdAt.toUtc().toIso8601String(),
      'updated_at': t.updatedAt.toUtc().toIso8601String(),
    };

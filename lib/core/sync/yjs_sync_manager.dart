import 'dart:convert';
import 'dart:developer' as dev;

import 'package:drift/drift.dart';
import 'package:dart_crdt/dart_crdt.dart';

import 'package:supanotes/features/notes/domain/yjs_task_entry.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import '../database/database.dart';

/// Manages a local Yjs [Doc] instance per note and persists binary
/// state snapshots to the [LocalYjsStates] Drift table.
///
/// Each note gets its own [Doc] instance. The binary state is loaded
/// from the local database on first access and flushed back on save.
class YjsSyncManager {
  YjsSyncManager({required AppDatabase db, required this.userId}) : _db = db;

  final String userId;

  final AppDatabase _db;

  /// In-memory per-note Yjs documents.
  final Map<String, Doc> _docs = {};

  /// Load the canonical [Doc] for [noteId].
  Future<Doc> loadDoc(String noteId) async {
    final cached = _docs[noteId];
    if (cached != null) return cached;

    final stateRow = await (_db.select(_db.localYjsStates)
          ..where((t) => t.noteId.equals(noteId)))
        .getSingleOrNull();
    if (stateRow != null) {
      final doc = Doc();
      try {
        applyUpdate(doc, stateRow.state);
        _migrateLegacyDoc(doc);
        _docs[noteId] = doc;
        dev.log('[YjsSyncManager] Loaded snapshot for note=$noteId', name: 'YjsSync');
        return doc;
      } catch (e, stackTrace) {
        dev.log('[YjsSyncManager] CRITICAL: Failed to apply snapshot for note=$noteId: $e. Clearing corrupted snapshot.',
            name: 'YjsSync', error: e, stackTrace: stackTrace);
        await (_db.delete(_db.localYjsStates)..where((t) => t.noteId.equals(noteId))).go();
        final doc = Doc();
        _migrateLegacyDoc(doc);
        _docs[noteId] = doc;
        dev.log('[YjsSyncManager] Initialized empty doc for note=$noteId after clearing corrupted snapshot. Waiting for server sync.', name: 'YjsSync');
        return doc;
      }
    }

    final doc = Doc();
    _migrateLegacyDoc(doc);
    _docs[noteId] = doc;
    dev.log('[YjsSyncManager] Initialized empty doc for note=$noteId. Waiting for WebSocket sync.', name: 'YjsSync');
    return doc;
  }

  Future<void> _persistLock = Future.value();

  /// WARNING: This function has a twin in backend/internal/sync/ydoc_service.go.
  /// Both must be kept in sync. The migration:
  ///   1. Detects legacy schema (completed field in node data)
  ///   2. Moves completed/dueDate/recurrence/lastCompletedAt to YMap("tasks")
  ///   3. Removes these fields from node data
  /// Schema is: YMap("nodes") -> {...} with data:{taskId?} and YMap("tasks") -> {taskId: JSON{nodeId,completed,title,dueDate,recurrence,lastCompletedAt}}
  ///
  /// Migrate a legacy doc (tasks inline in node `data`) to the P4 schema
  /// (tasks in `YMap("tasks")`, node `data` has only `taskId`).
  ///
  /// Idempotent: skips if `YMap("tasks")` already has entries.
  void _migrateLegacyDoc(Doc doc) {
    final tasksMap = doc.getMap('tasks');
    if (tasksMap.attrKeys.isNotEmpty) return;

    final nodesMap = doc.getMap('nodes');
    bool needsMigration = false;
    for (final key in nodesMap.attrKeys) {
      final raw = nodesMap.getAttr(key);
      if (raw is! String) continue;
      try {
        final meta = jsonDecode(raw) as Map<String, dynamic>;
        if (meta['type'] != 'task') continue;
        final data = meta['data'] as Map<String, dynamic>? ?? {};
        if (data.containsKey('completed')) {
          needsMigration = true;
          break;
        }
      } catch (e, st) {
          dev.log('[YjsSyncManager] migration detection error for key=$key', name: 'YjsSync', error: e, stackTrace: st);
        }
    }

    if (!needsMigration) return;

    dev.log('[YjsSyncManager] Migrating legacy doc schema to P4', name: 'YjsSync');
    doc.transact((txn) {
      for (final key in nodesMap.attrKeys) {
        final raw = nodesMap.getAttr(key);
        if (raw is! String) continue;
        try {
          final meta = jsonDecode(raw) as Map<String, dynamic>;
          if (meta['type'] != 'task') continue;
          final data = Map<String, dynamic>.from(meta['data'] as Map? ?? {});
          if (!data.containsKey('completed')) continue;

          final nodeId = meta['id'] as String;
          final completed = data['completed'] == true;
          final dueDate = data['dueDate'] as String?;
          final recurrence = data['recurrence'] as String?;
          final lastCompletedAt = data['lastCompletedAt'] as String?;
          final title = doc.getText('content/$nodeId').toPlainText();

          tasksMap.setAttr(nodeId, jsonEncode(_buildTaskEntry(
            nodeId,
            completed,
            title: title,
            dueDate: dueDate,
            recurrence: recurrence,
            lastCompletedAt: lastCompletedAt,
          )));

          data.remove('completed');
          data.remove('dueDate');
          data.remove('recurrence');
          data.remove('lastCompletedAt');
          meta['data'] = data;
          nodesMap.setAttr(key, jsonEncode(meta));
        } catch (e, st) {
            dev.log('[YjsSyncManager] migration error for key=$key', name: 'YjsSync', error: e, stackTrace: st);
          }
      }
    });
    dev.log('[YjsSyncManager] Legacy doc migration complete', name: 'YjsSync');
  }

  /// Persist the current in-memory Doc state for [noteId] to the database.
  Future<void> persist(String noteId) async {
    final doc = _docs[noteId];
    if (doc == null) return;
    final state = encodeStateAsUpdate(doc);
    _persistLock = _persistLock.then((_) async {
      try {
        await _db.into(_db.localYjsStates).insertOnConflictUpdate(
              LocalYjsStatesCompanion(
                noteId: Value(noteId),
                state: Value(state),
                updatedAt: Value(DateTime.now()),
              ),
            );
        dev.log('[YjsSyncManager] Persisted state for note=$noteId', name: 'YjsSync');
      } catch (e, stackTrace) {
        dev.log('YjsSyncManager persist error: $e', name: 'YjsSync', error: e, stackTrace: stackTrace, level: 1000);
      }
    });
    await _persistLock;
  }

  /// Project YMap("nodes") to local SQLite tables.
  /// Currently projects task nodes to the tasks table.
  Future<void> projectNodes(String noteId) async {
    final doc = _docs[noteId];
    if (doc == null) return;

    final nodesMap = doc.getMap('nodes');

    final tasks = <TasksCompanion>[];
    for (final key in nodesMap.attrKeys) {
      final raw = nodesMap.getAttr(key);
      if (raw == null) continue;
      try {
        final meta = jsonDecode(raw as String) as Map<String, dynamic>;
        if (meta['type'] != 'task') continue;
        final data = meta['data'] as Map<String, dynamic>? ?? {};
        final nodeId = meta['id'] as String;
        final text = doc.getText('content/$nodeId').toPlainText();

        final isComplete = data['completed'] == true;
        final taskEntry = YjsTaskEntry.decode(doc.getMap('tasks').getAttr(nodeId) as String?);
        final resolvedComplete = taskEntry?.completed == true || isComplete;

        final now = DateTime.now();

        DateTime? resolvedDueDate;
        TaskRecurrence? resolvedRecurrence;
        if (taskEntry != null) {
          if (taskEntry.dueDate != null) {
            resolvedDueDate = DateTime.tryParse('${taskEntry.dueDate}T00:00:00');
          }
          if (taskEntry.recurrence != null) {
            resolvedRecurrence = TaskRecurrence.parse(taskEntry.recurrence);
          }
        }

        tasks.add(TasksCompanion.insert(
          id: nodeId,
          userId: userId,
          noteId: noteId,
          title: text,
          status: resolvedComplete ? 'done' : 'open',
          position: Value((meta['position'] ?? '').toString()),
          dueDate: Value(resolvedDueDate),
          recurrence: Value(resolvedRecurrence),
          createdAt: now,
          updatedAt: now,
        ));
      } catch (e, st) {
        dev.log('[YjsSyncManager] projectNodes: failed to project node $key',
            name: 'YjsSync', error: e, stackTrace: st);
      }
    }

    if (tasks.isEmpty) return;

    final projectedIds = tasks.map((t) => t.id.value).toSet();
    await _db.transaction(() async {
      for (final task in tasks) {
        await _db.into(_db.tasks).insert(task, mode: InsertMode.insertOrReplace);
      }
      final existingRows = await (_db.select(_db.tasks)
        ..where((t) => t.noteId.equals(noteId))
      ).get();
      final toDelete = existingRows.where((r) => !projectedIds.contains(r.id)).toList();
      for (final row in toDelete) {
        await (_db.delete(_db.tasks)..where((t) => t.id.equals(row.id))).go();
      }
    });
  }

  Map<String, dynamic> _buildTaskEntry(String nodeId, bool completed, {String? title, String? dueDate, String? recurrence, String? lastCompletedAt}) {
    final entry = <String, dynamic>{
      'nodeId': nodeId,
      'completed': completed,
    };
    if (title != null) entry['title'] = title;
    if (dueDate != null) entry['dueDate'] = dueDate;
    if (recurrence != null) entry['recurrence'] = recurrence;
    if (lastCompletedAt != null) entry['lastCompletedAt'] = lastCompletedAt;
    return entry;
  }

  /// Evict the in-memory Doc for [noteId] so the next [loadDoc] re-reads from DB.
  void evictDoc(String noteId) {
    _docs.remove(noteId);
  }

  /// Dispose all in-memory Ydocs.
  void dispose() {
    _docs.clear();
  }
}

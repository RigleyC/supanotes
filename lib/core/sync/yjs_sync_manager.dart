import 'dart:convert';
import 'dart:developer' as dev;

import 'package:drift/drift.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'package:supanotes/features/notes/domain/yjs_node_codec.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import '../database/database.dart';

// Removed applyUpdateSafe since we will fix yjs_dart directly

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
  /// Both must be kept in sync.
  ///
  /// Migrates a legacy doc where nodes are stored as JSON strings in the
  /// YMap("nodes") map into nested YMap entries. Task fields (completed,
  /// dueDate, recurrence, lastCompletedAt) are promoted to top-level YMap keys.
  ///
  /// Idempotent: skips if any node is already a YMap.
  void _migrateLegacyDoc(Doc doc) {
    final nodesMap = doc.getMap<Object>('nodes')!;

    bool needsMigration = false;
    for (final key in nodesMap.keys) {
      if (key.contains(':')) continue;
      final raw = nodesMap.get(key);
      if (raw is YMap) continue;
      if (raw is String) {
        needsMigration = true;
        break;
      }
    }

    if (!needsMigration) return;

    dev.log('[YjsSyncManager] Migrating legacy doc to nested YMap schema', name: 'YjsSync');
    doc.transact((txn) {
      for (final key in nodesMap.keys) {
        if (key.contains(':')) continue;
        final raw = nodesMap.get(key);
        if (raw is! String) continue;
        try {
          final meta = jsonDecode(raw) as Map<String, dynamic>;

          final nodeMap = YMap<Object>();
          nodeMap.set('id', meta['id'] as String? ?? key);
          nodeMap.set('parentId', meta['parentId'] as String? ?? '');
          nodeMap.set('position', meta['position']?.toString() ?? 'a0');
          nodeMap.set('type', meta['type'] as String? ?? 'paragraph');

          if (meta['type'] == 'task') {
            final data = Map<String, dynamic>.from(meta['data'] as Map? ?? {});
            if (data.containsKey('completed')) {
              nodeMap.set('completed', data['completed'] == true);
            }
            if (data.containsKey('dueDate')) {
              nodeMap.set('dueDate', data['dueDate'] as String);
            }
            if (data.containsKey('recurrence')) {
              nodeMap.set('recurrence', data['recurrence'] as String);
            }
            if (data.containsKey('lastCompletedAt')) {
              nodeMap.set('lastCompletedAt', data['lastCompletedAt'] as String);
            }
            // Remove task fields from data before storing
            data.remove('completed');
            data.remove('dueDate');
            data.remove('recurrence');
            data.remove('lastCompletedAt');
            nodeMap.set('data', jsonEncode(data));
          } else {
            final dataRaw = meta['data'];
            if (dataRaw is String || dataRaw is num || dataRaw is bool) {
              nodeMap.set('data', dataRaw);
            } else {
              nodeMap.set('data', jsonEncode(dataRaw ?? {}));
            }
          }

          nodeMap.set('createdAt', meta['createdAt'] as num? ?? 0);
          nodesMap.set(key, nodeMap);
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

  /// Projects a raw Yjs state into local SQLite tables.
  /// Used by SyncService to project the state after a pull without
  /// affecting the active editor document.
  Future<void> projectState(String noteId, Uint8List state) async {
    final doc = Doc();
    applyUpdate(doc, state);
    _migrateLegacyDoc(doc);
    
    final previousDoc = _docs[noteId];
    _docs[noteId] = doc;
    try {
      await projectNodes(noteId);
    } finally {
      if (previousDoc != null) {
        _docs[noteId] = previousDoc;
      } else {
        _docs.remove(noteId);
      }
    }
  }

  /// Project YMap("nodes") to local SQLite tables.
  /// Projects task nodes to the tasks table and derives the note's
  /// content/excerpt so list views reflect edits without waiting for a
  /// sync round-trip.
  Future<void> projectNodes(String noteId) async {
    final doc = _docs[noteId];
    if (doc == null) return;

    final nodesMap = doc.getMap<Object>('nodes')!;

    final tasks = <TasksCompanion>[];
    for (final key in nodesMap.keys) {
      if (key.contains(':')) continue;
      final raw = nodesMap.get(key);
      if (raw == null) continue;

      String type = '';
      String nodeId = '';
      String? position;
      bool completed = false;
      String? dueDate;
      bool hasTime = false;
      String? recurrence;

      if (raw is YMap) {
        type = raw.get('type') as String? ?? '';
        if (type != 'task') continue;
        nodeId = raw.get('id') as String? ?? key;
        position = raw.get('position')?.toString();
        
        completed = nodesMap.get('$nodeId:completed') == true || raw.get('completed') == true;
        dueDate = (nodesMap.get('$nodeId:dueDate') as String?) ?? (raw.get('dueDate') as String?);
        hasTime = nodesMap.get('$nodeId:hasTime') == true || raw.get('hasTime') == true;
        recurrence = (nodesMap.get('$nodeId:recurrence') as String?) ?? (raw.get('recurrence') as String?);
      } else if (raw is String) {
        // Legacy fallback for un-migrated nodes
        try {
          final meta = jsonDecode(raw) as Map<String, dynamic>;
          if (meta['type'] != 'task') continue;
          nodeId = meta['id'] as String;
          position = meta['position']?.toString();
          final data = Map<String, dynamic>.from(meta['data'] as Map? ?? {});
          completed = nodesMap.get('$nodeId:completed') == true || data['completed'] == true;
          dueDate = (nodesMap.get('$nodeId:dueDate') as String?) ?? (data['dueDate'] as String?);
          hasTime = nodesMap.get('$nodeId:hasTime') == true || data['hasTime'] == true;
          recurrence = (nodesMap.get('$nodeId:recurrence') as String?) ?? (data['recurrence'] as String?);
        } catch (e) {
          dev.log('[YjsSyncManager] projectNodes: failed to parse legacy node $key', name: 'YjsSync', error: e);
          continue;
        }
      } else {
        continue;
      }

      String text = '';
      try {
        final sharedType = doc.get('content/$nodeId');
        if (sharedType is YText) {
          text = sharedType.toString();
        }
      } catch (e) {
        // Fallback if type is corrupted
      }

      final now = DateTime.now();

      DateTime? resolvedDueDate;
      TaskRecurrence? resolvedRecurrence;
      if (dueDate != null) {
        if (dueDate.contains('T')) {
          resolvedDueDate = DateTime.tryParse(dueDate);
        } else {
          resolvedDueDate = DateTime.tryParse('${dueDate}T00:00:00');
        }
      }
      if (recurrence != null) {
        resolvedRecurrence = TaskRecurrence.parse(recurrence);
      }

      tasks.add(TasksCompanion.insert(
        id: nodeId,
        userId: userId,
        noteId: noteId,
        title: text,
        status: completed ? 'done' : 'open',
        position: Value(position ?? ''),
        dueDate: Value(resolvedDueDate),
        hasTime: Value(hasTime),
        recurrence: Value(resolvedRecurrence),
        createdAt: now,
        updatedAt: now,
      ));
    }

    final projectedIds = tasks.map((t) => t.id.value).toSet();
    final content = _deriveMarkdownFromDoc(doc);
    final excerpt = _excerptFrom(content);
    final now = DateTime.now();

    await _db.transaction(() async {
      await _db.notesDao.updateNote(
        NotesCompanion(
          id: Value(noteId),
          content: Value(content),
          excerpt: Value(excerpt),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      );

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

  String _deriveMarkdownFromDoc(Doc doc) {
    final nodes = noteNodesFromDoc(doc);
    if (nodes.isEmpty) return '';

    final lines = <String>[];
    for (final node in nodes) {
      String text = '';
      try {
        final sharedType = doc.get('content/${node.id}');
        if (sharedType is YText) {
          text = sharedType.toString();
        }
      } catch (e) {
        // Fallback for corrupted type
      }
      switch (node.type) {
        case 'header':
          int level = 1;
          try {
            final data = jsonDecode(node.data) as Map<String, dynamic>;
            level = data['level'] as int? ?? 1;
          } catch (_) {}
          final prefix = List.filled(level, '#').join('');
          lines.add('$prefix $text');
        case 'task':
          final completed = _isTaskCompleted(doc, node.id);
          lines.add('- [${completed ? 'x' : ' '}] $text');
        case 'list_item':
          lines.add('- $text');
        case 'divider':
          lines.add('---');
        case 'image':
          lines.add('[image]');
        default:
          lines.add(text);
      }
    }
    return lines.join('\n');
  }

  bool _isTaskCompleted(Doc doc, String nodeId) {
    final raw = doc.getMap<Object>('nodes')!.get(nodeId);
    if (raw is YMap) {
      return raw.get('completed') == true;
    }
    if (raw is! String) return false;
    try {
      final meta = jsonDecode(raw) as Map<String, dynamic>;
      final data = meta['data'] as Map<String, dynamic>? ?? {};
      return data['completed'] == true;
    } catch (_) {
      return false;
    }
  }

  String? _excerptFrom(String content) {
    if (content.isEmpty) return null;
    final lines = content.split('\n');
    int firstNonEmptyIdx = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].trim().isNotEmpty) {
        firstNonEmptyIdx = i;
        break;
      }
    }
    if (firstNonEmptyIdx == -1) return null;
    final restOfLines = lines.skip(firstNonEmptyIdx + 1).join('\n');
    final flat = restOfLines.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.isEmpty) return null;
    if (flat.length <= 120) return flat;
    return '${flat.substring(0, 120)}…';
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

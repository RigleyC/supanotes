import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'package:supanotes/features/notes/domain/yjs_node_codec.dart';
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
        _docs[noteId] = doc;
        dev.log('[YjsSyncManager] Loaded snapshot for note=$noteId', name: 'YjsSync');
        return doc;
      } catch (e, stackTrace) {
        dev.log('[YjsSyncManager] CRITICAL: Failed to apply snapshot for note=$noteId: $e. Clearing corrupted snapshot.',
            name: 'YjsSync', error: e, stackTrace: stackTrace);
        await (_db.delete(_db.localYjsStates)..where((t) => t.noteId.equals(noteId))).go();
        final doc = Doc();
        _docs[noteId] = doc;
        dev.log('[YjsSyncManager] Initialized empty doc for note=$noteId after clearing corrupted snapshot. Waiting for server sync.', name: 'YjsSync');
        return doc;
      }
    }

    final doc = Doc();
    _docs[noteId] = doc;
    dev.log('[YjsSyncManager] Initialized empty doc for note=$noteId. Waiting for server sync.', name: 'YjsSync');
    return doc;
  }

  Future<void> _persistLock = Future.value();

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
    
    final previousDoc = _docs[noteId];
    _docs[noteId] = doc;
    try {
      await projectNodes(noteId, markDirty: false);
    } finally {
      if (previousDoc != null) {
        _docs[noteId] = previousDoc;
      } else {
        _docs.remove(noteId);
      }
    }
  }

  /// Per-note serial write chains to avoid concurrent projection for the same note.
  final Map<String, Future<void>> _noteWriteChains = {};

  /// Project YMap("nodes") to local SQLite tables.
  /// Projects task nodes to the tasks table and derives the note's
  /// content/excerpt so list views reflect edits without waiting for a
  /// sync round-trip.
  Future<void> projectNodes(String noteId, {bool markDirty = true}) async {
    if (!_noteWriteChains.containsKey(noteId)) {
      _noteWriteChains[noteId] = Future.value();
    }
    _noteWriteChains[noteId] = _noteWriteChains[noteId]!.then((_) => _projectNow(noteId, markDirty: markDirty));
    return _noteWriteChains[noteId];
  }

  Future<void> _projectNow(String noteId, {bool markDirty = true}) async {
    final doc = _docs[noteId];
    if (doc == null) return;

    final data = deriveProjectedData(noteId, doc, userId, markDirty: markDirty);
    final existingRows = await (_db.select(_db.tasks)
      ..where((t) => t.noteId.equals(noteId))
    ).get();

    // Indexed reconciliation: build map for O(1) lookups
    final existingById = {for (final row in existingRows) row.id: row};

    await _db.batch((batch) {
      batch.update(
        _db.notes,
        data.noteCompanion,
        where: (t) => t.id.equals(noteId),
      );
      
      for (final task in data.tasks) {
        final existing = existingById.remove(task.id.value);
        if (existing == null) {
          batch.insert(_db.tasks, task);
        } else {
          // Only write if something changed
          bool changed = false;
          if (existing.title != task.title.value) changed = true;
          if (existing.status != task.status.value) changed = true;
          if (existing.position != task.position.value) changed = true;
          if (existing.dueDate != task.dueDate.value) changed = true;
          if (existing.hasTime != task.hasTime.value) changed = true;
          if (existing.recurrence != task.recurrence.value) changed = true;
          if (existing.reminder != task.reminder.value) changed = true;
          if (existing.completedAt != task.completedAt.value) changed = true;
          
          if (changed) {
            batch.update(
              _db.tasks,
              task.copyWith(createdAt: Value(existing.createdAt)),
              where: (t) => t.id.equals(existing.id),
            );
          }
        }
      }
      
      // Delete orphan tasks that no longer exist in the YDoc
      for (final orphan in existingById.values) {
        batch.delete(_db.tasks, orphan);
      }
    });

    // Clean up resolved write chain entry
    _noteWriteChains.remove(noteId);
  }

  /// Persist the current in-memory Doc state with the synced state vector.
  Future<void> persistWithSyncedVector(String noteId, Uint8List? syncedStateVector) async {
    final doc = _docs[noteId];
    if (doc == null) return;
    final state = encodeStateAsUpdate(doc);
    await _db.into(_db.localYjsStates).insertOnConflictUpdate(
      LocalYjsStatesCompanion(
        noteId: Value(noteId),
        state: Value(state),
        syncedStateVector: Value(syncedStateVector),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Merges remote Yjs states into local states and projects the result.
  /// Merges remote Yjs states into local states and projects the result.
  Future<void> mergeRemoteStatesAndProject({
    required List<Map<String, dynamic>> rawYjsStates,
    required bool Function(String) isActiveNote,
    required void Function(String) onMerged,
  }) async {
    if (rawYjsStates.isEmpty) return;

    final noteIdsToProject = rawYjsStates.map((raw) => raw['note_id'] as String).toList();
    
    final localStatesList = noteIdsToProject.isEmpty ? <LocalYjsState>[] : await (_db.select(_db.localYjsStates)..where((t) => t.noteId.isIn(noteIdsToProject))).get();
    final localStatesMap = {for (final s in localStatesList) s.noteId: s.state};
    
    final existingTasksList = noteIdsToProject.isEmpty ? <TaskData>[] : await (_db.select(_db.tasks)..where((t) => t.noteId.isIn(noteIdsToProject))).get();
    final existingTasksByNote = <String, List<TaskData>>{};
    for (final t in existingTasksList) {
      existingTasksByNote.putIfAbsent(t.noteId, () => []).add(t);
    }

    String? activeNoteId;
    for (final noteId in noteIdsToProject) {
      if (isActiveNote(noteId)) {
        activeNoteId = noteId;
        break;
      }
    }

    final params = IsolateMergeParams(
      rawYjsStates: rawYjsStates,
      localStatesMap: localStatesMap,
      existingTasksByNote: existingTasksByNote,
      activeNoteId: activeNoteId,
      currentUserId: userId,
    );

    // Run the CPU-heavy Yjs merging logic in a background isolate to prevent ANRs
    final result = await compute(_mergeRemoteStatesAndProjectIsolate, params);

    for (final noteId in result.mergedNoteIds) {
      evictDoc(noteId);
      onMerged(noteId);
    }

    if (result.yjsStatesToInsert.isNotEmpty || 
        result.projectedNotes.isNotEmpty || 
        result.projectedTasks.isNotEmpty || 
        result.tasksToDelete.isNotEmpty) {
      await _db.batch((batch) {
        for (final state in result.yjsStatesToInsert) {
          batch.insert(_db.localYjsStates, state, onConflict: DoUpdate((_) => state));
        }
        for (final note in result.projectedNotes) {
          batch.update(
            _db.notes,
            note,
            where: (t) => t.id.equals(note.id.value),
          );
        }
        for (final task in result.projectedTasks) {
          batch.insert(_db.tasks, task, mode: InsertMode.insertOrReplace);
        }
        for (final task in result.tasksToDelete) {
          batch.delete(_db.tasks, task);
        }
      });
    }
  }

  static ProjectedData deriveProjectedData(String noteId, Doc doc, String userId, {bool markDirty = true}) {
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
      String? reminder;
      DateTime? completedAt;

      if (raw is YMap) {
        type = raw.get('type') as String? ?? '';
        if (type != 'task') continue;
        nodeId = raw.get('id') as String? ?? key;
        position = raw.get('position')?.toString();
        
        completed = nodesMap.get('$nodeId:completed') == true || raw.get('completed') == true;
        dueDate = (nodesMap.get('$nodeId:dueDate') as String?) ?? (raw.get('dueDate') as String?);
        hasTime = nodesMap.get('$nodeId:hasTime') == true || raw.get('hasTime') == true;
        recurrence = (nodesMap.get('$nodeId:recurrence') as String?) ?? (raw.get('recurrence') as String?);
        reminder = (nodesMap.get('$nodeId:reminder') as String?) ?? (raw.get('reminder') as String?);
        
        final lastCompletedAtStr = (nodesMap.get('$nodeId:lastCompletedAt') as String?) ?? (raw.get('lastCompletedAt') as String?);
        if (lastCompletedAtStr != null) {
          completedAt = DateTime.tryParse(lastCompletedAtStr);
        }
      } else {
        continue;
      }

      final nodeData = _extractNodeData(raw);
      final text = _readNodeTextContent(doc, nodeId, nodeData: nodeData);

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
        reminder: Value(reminder),
        completedAt: Value(completedAt),
        createdAt: now,
        updatedAt: now,
      ));
    }

    final content = _deriveMarkdownFromDoc(doc);
    final excerpt = _excerptFrom(content);
    final now = DateTime.now();

    final companion = NotesCompanion(
      id: Value(noteId),
      content: Value(content),
      excerpt: Value(excerpt),
      updatedAt: Value(now),
    );
    final finalCompanion = markDirty ? companion.copyWith(isDirty: const Value(true)) : companion;

    return ProjectedData(finalCompanion, tasks);
  }

  static String _deriveMarkdownFromDoc(Doc doc) {
    final nodes = noteNodesFromDoc(doc);
    if (nodes.isEmpty) return '';

    final lines = <String>[];
    for (final node in nodes) {
      final nodeData = node.data;
      final text = _readNodeTextContent(doc, node.id, nodeData: nodeData);
      switch (node.type) {
        case 'header':
          int level = 1;
          try {
            level = node.data['level'] as int? ?? 1;
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

  static bool _isTaskCompleted(Doc doc, String nodeId) {
    final raw = doc.getMap<Object>('nodes')!.get(nodeId);
    if (raw is YMap) {
      return raw.get('completed') == true;
    }
    return false;
  }

  static String? _excerptFrom(String content) {
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

  static String _readNodeTextContent(
    Doc doc,
    String nodeId, {
    Map<String, dynamic>? nodeData,
  }) {
    final fixedKey = 'content_fixed/$nodeId';
    if (doc.share.containsKey(fixedKey)) {
      try {
        final fixedType = doc.getText(fixedKey);
        if (fixedType != null) {
          final text = fixedType.toString();
          if (text.isNotEmpty) return text;
        }
      } catch (_) {}
    }

    final contentKey = 'content/$nodeId';
    if (doc.share.containsKey(contentKey)) {
      try {
        final sharedType = doc.getText(contentKey);
        if (sharedType != null) {
          final text = sharedType.toString();
          if (text.isNotEmpty) return text;
        }
      } catch (_) {}
    }

    final dataText = nodeData?['text'] as String?;
    if (dataText != null && dataText.isNotEmpty) return dataText;

    return '';
  }

  static Map<String, dynamic>? _extractNodeData(dynamic raw) {
    if (raw is YMap) {
      final dataRaw = raw.get('data');
      if (dataRaw is String) {
        return _jsonMapFromString(dataRaw);
      }
    }
    return null;
  }

  static Map<String, dynamic>? _jsonMapFromString(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    } catch (_) {}
    return null;
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

class IsolateMergeParams {
  final List<Map<String, dynamic>> rawYjsStates;
  final Map<String, List<int>> localStatesMap;
  final Map<String, List<TaskData>> existingTasksByNote;
  final String? activeNoteId;
  final String? currentUserId;

  IsolateMergeParams({
    required this.rawYjsStates,
    required this.localStatesMap,
    required this.existingTasksByNote,
    required this.activeNoteId,
    required this.currentUserId,
  });
}

class IsolateMergeResult {
  final List<LocalYjsStatesCompanion> yjsStatesToInsert;
  final List<NotesCompanion> projectedNotes;
  final List<TasksCompanion> projectedTasks;
  final List<TaskData> tasksToDelete;
  final List<String> mergedNoteIds;

  IsolateMergeResult({
    required this.yjsStatesToInsert,
    required this.projectedNotes,
    required this.projectedTasks,
    required this.tasksToDelete,
    required this.mergedNoteIds,
  });
}

IsolateMergeResult _mergeRemoteStatesAndProjectIsolate(IsolateMergeParams params) {
  final projectedNotes = <NotesCompanion>[];
  final projectedTasks = <TasksCompanion>[];
  final yjsStatesToInsert = <LocalYjsStatesCompanion>[];
  final tasksToDelete = <TaskData>[];
  final mergedNoteIds = <String>[];

  final userId = params.currentUserId;
  if (userId == null) {
    return IsolateMergeResult(
      yjsStatesToInsert: [],
      projectedNotes: [],
      projectedTasks: [],
      tasksToDelete: [],
      mergedNoteIds: [],
    );
  }

  for (final raw in params.rawYjsStates) {
    final noteId = raw['note_id'] as String;
    if (params.activeNoteId == noteId) {
      continue;
    }

    final rawState = raw['state'];
    List<int> remoteStateBytes;
    if (rawState is String) {
      remoteStateBytes = base64Decode(rawState);
    } else {
      remoteStateBytes = (rawState as List).cast<int>();
    }
    
    final remoteUpdatedAtStr = raw['updated_at'] as String;
    final remoteUpdatedAt = DateTime.parse(remoteUpdatedAtStr);

    final tmpDoc = Doc();
    try {
      final localStateBytes = params.localStatesMap[noteId];
      if (localStateBytes != null) {
        applyUpdate(tmpDoc, Uint8List.fromList(localStateBytes));
      }
      applyUpdate(tmpDoc, Uint8List.fromList(remoteStateBytes));

      final mergedState = encodeStateAsUpdate(tmpDoc);
      yjsStatesToInsert.add(LocalYjsStatesCompanion(
        noteId: Value(noteId),
        state: Value(mergedState),
        updatedAt: Value(DateTime.now()),
      ));
      
      final projectedData = YjsSyncManager.deriveProjectedData(noteId, tmpDoc, userId, markDirty: false);
      projectedNotes.add(projectedData.noteCompanion.copyWith(hasRemoteCopy: const Value(true)));
      projectedTasks.addAll(projectedData.tasks);
      
      final projectedTaskIds = projectedData.tasks.map((t) => t.id.value).toSet();
      final noteExistingTasks = params.existingTasksByNote[noteId] ?? [];
      tasksToDelete.addAll(noteExistingTasks.where((t) => !projectedTaskIds.contains(t.id)));

      mergedNoteIds.add(noteId);
    } catch (e, st) {
      debugPrint('[IsolateYjsSync] mergeRemoteStatesAndProject ERROR: $e\n$st');
      yjsStatesToInsert.add(LocalYjsStatesCompanion(
        noteId: Value(noteId),
        state: Value(Uint8List.fromList(remoteStateBytes)),
        updatedAt: Value(remoteUpdatedAt),
      ));
      
      final fallbackDoc = Doc();
      applyUpdate(fallbackDoc, Uint8List.fromList(remoteStateBytes));
      final projectedData = YjsSyncManager.deriveProjectedData(noteId, fallbackDoc, userId, markDirty: false);
      projectedNotes.add(projectedData.noteCompanion.copyWith(hasRemoteCopy: const Value(true)));
      projectedTasks.addAll(projectedData.tasks);
      
      final projectedTaskIds = projectedData.tasks.map((t) => t.id.value).toSet();
      final noteExistingTasks = params.existingTasksByNote[noteId] ?? [];
      tasksToDelete.addAll(noteExistingTasks.where((t) => !projectedTaskIds.contains(t.id)));

      mergedNoteIds.add(noteId);
    }
  }

  return IsolateMergeResult(
    yjsStatesToInsert: yjsStatesToInsert,
    projectedNotes: projectedNotes,
    projectedTasks: projectedTasks,
    tasksToDelete: tasksToDelete,
    mergedNoteIds: mergedNoteIds,
  );
}

class ProjectedData {
  final NotesCompanion noteCompanion;
  final List<TasksCompanion> tasks;
  ProjectedData(this.noteCompanion, this.tasks);
}

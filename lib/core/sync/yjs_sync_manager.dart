import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'package:uuid/uuid.dart';

import 'package:supanotes/core/utils/recurrence.dart';
import 'package:supanotes/features/notes/domain/yjs_note_schema.dart';
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

    final stateRow = await (_db.select(
      _db.localYjsStates,
    )..where((t) => t.noteId.equals(noteId))).getSingleOrNull();
    if (stateRow != null) {
      final doc = Doc();
      try {
        applyUpdate(doc, stateRow.state);
        _docs[noteId] = doc;
        dev.log(
          '[YjsSyncManager] Loaded snapshot for note=$noteId',
          name: 'YjsSync',
        );
        return doc;
      } catch (e, stackTrace) {
        dev.log(
          '[YjsSyncManager] CRITICAL: Failed to apply snapshot for note=$noteId: $e. Clearing corrupted snapshot.',
          name: 'YjsSync',
          error: e,
          stackTrace: stackTrace,
        );
        await (_db.delete(
          _db.localYjsStates,
        )..where((t) => t.noteId.equals(noteId))).go();
        final doc = Doc();
        _docs[noteId] = doc;
        dev.log(
          '[YjsSyncManager] Initialized empty doc for note=$noteId after clearing corrupted snapshot. Waiting for server sync.',
          name: 'YjsSync',
        );
        return doc;
      }
    }

    final doc = Doc();
    _docs[noteId] = doc;
    dev.log(
      '[YjsSyncManager] Initialized empty doc for note=$noteId. Waiting for server sync.',
      name: 'YjsSync',
    );
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
        await _db
            .into(_db.localYjsStates)
            .insertOnConflictUpdate(
              LocalYjsStatesCompanion(
                noteId: Value(noteId),
                state: Value(state),
                updatedAt: Value(DateTime.now()),
              ),
            );
        dev.log(
          '[YjsSyncManager] Persisted state for note=$noteId',
          name: 'YjsSync',
        );
      } catch (e, stackTrace) {
        dev.log(
          'YjsSyncManager persist error: $e',
          name: 'YjsSync',
          error: e,
          stackTrace: stackTrace,
          level: 1000,
        );
      }
    });
    await _persistLock;
  }

  /// Per-note serial write chains to avoid concurrent projection for the same note.
  /// Uses a generation counter to avoid the race where an old projection removes
  /// a chain entry that a newer projection was chained onto.
  final Map<String, Future<void>> _noteWriteChains = {};
  final Map<String, int> _noteWriteGenerations = {};

  /// Project YMap("nodes") to local SQLite tables.
  /// Projects task nodes to the tasks table and derives the note's
  /// content/excerpt so list views reflect edits without waiting for a
  /// sync round-trip.
  ///
  /// Errors propagate to the caller so it can react (e.g., signal staleness).
  /// The internal chain recovers via the generation counter so subsequent
  /// calls still execute.
  Future<void> projectNodes(String noteId, {bool markDirty = true}) async {
    if (!_noteWriteChains.containsKey(noteId)) {
      _noteWriteChains[noteId] = Future.value();
      _noteWriteGenerations[noteId] = 0;
    }
    final gen = (_noteWriteGenerations[noteId] ?? 0) + 1;
    _noteWriteGenerations[noteId] = gen;

    // inner: the operation future that IS allowed to reject
    final inner = _noteWriteChains[noteId]!.then((_) async {
      try {
        await _projectNow(noteId, markDirty: markDirty);
      } finally {
        if (_noteWriteGenerations[noteId] == gen) {
          _noteWriteChains.remove(noteId);
          _noteWriteGenerations.remove(noteId);
        }
      }
    });

    // Chain entry gets a safe version that never rejects:
    // the internal chain survives even when individual operations fail.
    _noteWriteChains[noteId] = inner.catchError((_) {});

    // Caller receives the real future — errors are propagated.
    return inner;
  }

  Future<void> _projectNow(String noteId, {bool markDirty = true}) async {
    final doc = _docs[noteId];
    if (doc == null) return;

    final data = deriveProjectedData(noteId, doc, userId, markDirty: markDirty);
    final existingRows = await (_db.select(
      _db.tasks,
    )..where((t) => t.noteId.equals(noteId))).get();

    // Indexed reconciliation: build map for O(1) lookups
    final existingById = {for (final row in existingRows) row.id: row};

    final existingNote = await (_db.select(
      _db.notes,
    )..where((t) => t.id.equals(noteId))).getSingleOrNull();

    bool noteChanged = markDirty;
    if (existingNote != null) {
      final companion = data.noteCompanion;
      if (companion.content.value != existingNote.content) noteChanged = true;
      if (companion.excerpt.value != existingNote.excerpt) noteChanged = true;
    } else {
      noteChanged = true;
    }

    final recurringTaskIds = data.tasks
        .where((task) => task.recurrence.value != null)
        .map((task) => task.id.value)
        .toList(growable: false);
    final existingRecurringCompletions = recurringTaskIds.isEmpty
        ? const <LocalTaskCompletionData>[]
        : await (_db.select(_db.localTaskCompletions)..where(
                (completion) => completion.taskId.isIn(recurringTaskIds),
              ))
              .get();

    await _db.batch((batch) {
      if (noteChanged) {
        batch.update(
          _db.notes,
          data.noteCompanion,
          where: (t) => t.id.equals(noteId),
        );
      }

      for (final task in data.tasks) {
        final existing = existingById.remove(task.id.value);
        if (existing == null) {
          batch.insert(_db.tasks, task);
        } else {
          // Only write if something changed
          bool changed = false;
          if (existing.title != task.title.value) {
            changed = true;
          }
          if (existing.status != task.status.value) {
            changed = true;
          }
          if (existing.position != task.position.value) changed = true;
          if (existing.dueDate?.toUtc() != task.dueDate.value?.toUtc()) {
            changed = true;
          }
          if (existing.hasTime != task.hasTime.value) changed = true;
          if (existing.recurrence != task.recurrence.value) changed = true;
          if (existing.reminder != task.reminder.value) changed = true;
          if (existing.completedAt?.toUtc() !=
              task.completedAt.value?.toUtc()) {
            changed = true;
          }

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

      // Recurring completion events are a projection of the YDoc. Replace the
      // note's recurring history so deleted YMap entries (undo) are deleted
      // locally as well.
      for (final completion in existingRecurringCompletions) {
        batch.delete(_db.localTaskCompletions, completion);
      }

      // Upsert task completions projected from the YDoc.
      for (final completion in data.completions) {
        batch.insert(
          _db.localTaskCompletions,
          completion,
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  /// Persist the current in-memory Doc state with the synced state vector.
  /// Always re-encodes — the cache is not safe because the YDoc may have
  /// changed (e.g. after applying a remote update).
  Future<void> persistWithSyncedVector(
    String noteId,
    Uint8List? syncedStateVector,
  ) async {
    final doc = _docs[noteId];
    if (doc == null) return;
    final state = encodeStateAsUpdate(doc);
    try {
      await _db
          .into(_db.localYjsStates)
          .insertOnConflictUpdate(
            LocalYjsStatesCompanion(
              noteId: Value(noteId),
              state: Value(state),
              syncedStateVector: Value(syncedStateVector),
              updatedAt: Value(DateTime.now()),
            ),
          );
      dev.log(
        '[YjsSyncManager] Persisted synced vector for note=$noteId',
        name: 'YjsSync',
      );
    } catch (e, stackTrace) {
      dev.log(
        'YjsSyncManager persistWithSyncedVector error: $e',
        name: 'YjsSync',
        error: e,
        stackTrace: stackTrace,
        level: 1000,
      );
    }
  }

  /// Merges remote Yjs states into local states and projects the result.
  /// Merges remote Yjs states into local states and projects the result.
  Future<void> mergeRemoteStatesAndProject({
    required List<Map<String, dynamic>> rawYjsStates,
    required bool Function(String) isActiveNote,
    required void Function(String) onMerged,
  }) async {
    if (rawYjsStates.isEmpty) return;

    final noteIdsToProject = rawYjsStates
        .map((raw) => raw['note_id'] as String)
        .toList();

    final localStatesList = noteIdsToProject.isEmpty
        ? <LocalYjsState>[]
        : await (_db.select(
            _db.localYjsStates,
          )..where((t) => t.noteId.isIn(noteIdsToProject))).get();
    final localStatesMap = {for (final s in localStatesList) s.noteId: s.state};

    final existingTasksList = noteIdsToProject.isEmpty
        ? <TaskData>[]
        : await (_db.select(
            _db.tasks,
          )..where((t) => t.noteId.isIn(noteIdsToProject))).get();
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

    // Estimate total byte cost: remote states (base64 ≈ ¾ of string length)
    // + local states.  If the total is below 256 KB, run inline to avoid
    // Isolate spawning overhead (~1.8 s penalty on mobile).
    int totalBytes = 0;
    for (final raw in rawYjsStates) {
      final rawState = raw['state'];
      if (rawState is String) {
        totalBytes += rawState.length * 3 ~/ 4;
      } else if (rawState is List) {
        totalBytes += rawState.length;
      }
    }
    for (final localState in localStatesMap.values) {
      totalBytes += localState.length;
    }

    const int kInlineThreshold = 256 * 1024; // 256 KB
    final IsolateMergeResult result;
    if (totalBytes < kInlineThreshold && rawYjsStates.length <= 5) {
      result = _mergeRemoteStatesAndProjectIsolate(params);
    } else {
      result = await compute(_mergeRemoteStatesAndProjectIsolate, params);
    }

    for (final noteId in result.mergedNoteIds) {
      evictDoc(noteId);
      onMerged(noteId);
    }

    if (result.yjsStatesToInsert.isNotEmpty ||
        result.projectedNotes.isNotEmpty ||
        result.projectedTasks.isNotEmpty ||
        result.projectedCompletions.isNotEmpty ||
        result.tasksToDelete.isNotEmpty) {
      await _db.batch((batch) {
        for (final state in result.yjsStatesToInsert) {
          batch.insert(
            _db.localYjsStates,
            state,
            onConflict: DoUpdate((_) => state),
          );
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
        for (final completion in result.projectedCompletions) {
          batch.insert(
            _db.localTaskCompletions,
            completion,
            mode: InsertMode.insertOrReplace,
          );
        }
        for (final task in result.tasksToDelete) {
          batch.delete(_db.tasks, task);
        }
      });
    }
  }

  static ProjectedData deriveProjectedData(
    String noteId,
    Doc doc,
    String userId, {
    bool markDirty = true,
  }) {
    final nodes = noteNodesFromDoc(doc);
    final nodesMap = doc.getMap<Object>('nodes')!;
    final now = DateTime.now();

    // Single pass: build markdown lines AND extract task metadata
    final lines = <String>[];
    final tasks = <TasksCompanion>[];

    for (final node in nodes) {
      final text = YjsNoteSchema.readNodeTextContent(
        doc,
        node.id,
        nodeData: node.data,
      );

      // Build markdown line
      switch (node.type) {
        case 'header':
          final level = node.data['level'] as int? ?? 1;
          lines.add('${List.filled(level, '#').join()} $text');
        case 'task':
          final raw = nodesMap.get(node.id);
          final completed =
              raw is YMap &&
              (nodesMap.get('${node.id}:completed') == true ||
                  raw.get('completed') == true);
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

      // Extract task companion
      if (node.type == 'task') {
        final raw = nodesMap.get(node.id);
        if (raw is YMap) {
          final completed =
              nodesMap.get('${node.id}:completed') == true ||
              raw.get('completed') == true;
          final dueDate =
              (nodesMap.get('${node.id}:dueDate') as String?) ??
              (raw.get('dueDate') as String?);
          final hasTime =
              nodesMap.get('${node.id}:hasTime') == true ||
              raw.get('hasTime') == true;
          final recurrence =
              (nodesMap.get('${node.id}:recurrence') as String?) ??
              (raw.get('recurrence') as String?);
          final reminder =
              (nodesMap.get('${node.id}:reminder') as String?) ??
              (raw.get('reminder') as String?);
          final lastCompletedAtStr =
              (nodesMap.get('${node.id}:lastCompletedAt') as String?) ??
              (raw.get('lastCompletedAt') as String?);

          DateTime? completedAt;
          if (lastCompletedAtStr != null) {
            completedAt = DateTime.tryParse(lastCompletedAtStr);
          }

          DateTime? resolvedDueDate;
          if (dueDate != null) {
            resolvedDueDate = dueDate.contains('T')
                ? DateTime.tryParse(dueDate)
                : DateTime.tryParse('${dueDate}T00:00:00');
          }
          TaskRecurrence? resolvedRecurrence;
          if (recurrence != null) {
            resolvedRecurrence = TaskRecurrence.parse(recurrence);
          }

          tasks.add(
            TasksCompanion.insert(
              id: node.id,
              userId: userId,
              noteId: noteId,
              title: text,
              status: completed ? 'done' : 'open',
              position: Value(node.position),
              dueDate: Value(resolvedDueDate),
              hasTime: Value(hasTime),
              recurrence: Value(resolvedRecurrence),
              reminder: Value(reminder),
              completedAt: Value(completedAt),
              createdAt: now,
              updatedAt: now,
            ),
          );
        }
      }
    }

    // Project task completion events from YDoc's taskCompletions YMap
    final completions = <LocalTaskCompletionsCompanion>[];
    final taskCompletionsMap = doc.getMap<Object>(
      YjsNoteSchema.taskCompletionsRoot,
    );
    if (taskCompletionsMap != null) {
      for (final key in taskCompletionsMap.keys) {
        final colonIdx = key.indexOf(':');
        if (colonIdx == -1) continue;
        final taskId = key.substring(0, colonIdx);
        final scheduledAtStr = key.substring(colonIdx + 1);
        final value = taskCompletionsMap.get(key);
        if (value is! String) continue;

        final completedAt = DateTime.tryParse(value);
        final scheduledAt = scheduledAtStr.contains('T')
            ? DateTime.tryParse(scheduledAtStr)
            : DateTime.tryParse('${scheduledAtStr}T00:00:00');
        if (completedAt == null || scheduledAt == null) continue;

        final uuid = const Uuid().v4();
        completions.add(
          LocalTaskCompletionsCompanion.insert(
            id: uuid,
            taskId: taskId,
            userId: userId,
            completedAt: completedAt.toUtc(),
            scheduledAt: scheduledAt.toUtc(),
          ),
        );
      }
    }

    // Migration: recurring tasks with legacy completedAt but no taskCompletions
    // entries get one synthetic completion for the closest occurrence.
    final completedTaskIds = completions.map((c) => c.taskId.value).toSet();
    for (final task in tasks) {
      if (task.recurrence.value == null) continue;
      if (task.completedAt.value == null) continue;
      if (task.dueDate.value == null) continue;
      if (completedTaskIds.contains(task.id.value)) continue;

      final anchor = task.dueDate.value!;
      final completedAt = task.completedAt.value!;
      final recurrence = task.recurrence.value!;
      final legacyOccurrences = enumerateOccurrences(
        anchor: anchor,
        recurrence: recurrence,
        from: anchor,
        to: completedAt.isBefore(anchor) ? anchor : completedAt,
      );
      final scheduledAt = legacyOccurrences.isNotEmpty
          ? legacyOccurrences.last
          : anchor;

      final uuid = const Uuid().v4();
      completions.add(
        LocalTaskCompletionsCompanion.insert(
          id: uuid,
          taskId: task.id.value,
          userId: userId,
          completedAt: completedAt.toUtc(),
          scheduledAt: scheduledAt.toUtc(),
        ),
      );
    }

    final content = lines.join('\n');
    final excerpt = _excerptFrom(content);

    final companion = NotesCompanion(
      id: Value(noteId),
      content: Value(content),
      excerpt: Value(excerpt),
      updatedAt: Value(now),
    );
    final finalCompanion = markDirty
        ? companion.copyWith(isDirty: const Value(true))
        : companion;

    return ProjectedData(finalCompanion, tasks, completions: completions);
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
  final List<LocalTaskCompletionsCompanion> projectedCompletions;
  final List<TaskData> tasksToDelete;
  final List<String> mergedNoteIds;

  IsolateMergeResult({
    required this.yjsStatesToInsert,
    required this.projectedNotes,
    required this.projectedTasks,
    required this.projectedCompletions,
    required this.tasksToDelete,
    required this.mergedNoteIds,
  });
}

IsolateMergeResult _mergeRemoteStatesAndProjectIsolate(
  IsolateMergeParams params,
) {
  final projectedNotes = <NotesCompanion>[];
  final projectedTasks = <TasksCompanion>[];
  final projectedCompletions = <LocalTaskCompletionsCompanion>[];
  final yjsStatesToInsert = <LocalYjsStatesCompanion>[];
  final tasksToDelete = <TaskData>[];
  final mergedNoteIds = <String>[];

  final userId = params.currentUserId;
  if (userId == null) {
    return IsolateMergeResult(
      yjsStatesToInsert: [],
      projectedNotes: [],
      projectedTasks: [],
      projectedCompletions: [],
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
      yjsStatesToInsert.add(
        LocalYjsStatesCompanion(
          noteId: Value(noteId),
          state: Value(mergedState),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final projectedData = YjsSyncManager.deriveProjectedData(
        noteId,
        tmpDoc,
        userId,
        markDirty: false,
      );
      projectedNotes.add(
        projectedData.noteCompanion.copyWith(hasRemoteCopy: const Value(true)),
      );
      projectedCompletions.addAll(projectedData.completions);
      projectedTasks.addAll(projectedData.tasks);

      final projectedTaskIds = projectedData.tasks
          .map((t) => t.id.value)
          .toSet();
      final noteExistingTasks = params.existingTasksByNote[noteId] ?? [];
      tasksToDelete.addAll(
        noteExistingTasks.where((t) => !projectedTaskIds.contains(t.id)),
      );

      mergedNoteIds.add(noteId);
    } catch (e, st) {
      debugPrint('[IsolateYjsSync] mergeRemoteStatesAndProject ERROR: $e\n$st');
      yjsStatesToInsert.add(
        LocalYjsStatesCompanion(
          noteId: Value(noteId),
          state: Value(Uint8List.fromList(remoteStateBytes)),
          updatedAt: Value(remoteUpdatedAt),
        ),
      );

      final fallbackDoc = Doc();
      applyUpdate(fallbackDoc, Uint8List.fromList(remoteStateBytes));
      final projectedData = YjsSyncManager.deriveProjectedData(
        noteId,
        fallbackDoc,
        userId,
        markDirty: false,
      );
      projectedNotes.add(
        projectedData.noteCompanion.copyWith(hasRemoteCopy: const Value(true)),
      );
      projectedCompletions.addAll(projectedData.completions);
      projectedTasks.addAll(projectedData.tasks);

      final projectedTaskIds = projectedData.tasks
          .map((t) => t.id.value)
          .toSet();
      final noteExistingTasks = params.existingTasksByNote[noteId] ?? [];
      tasksToDelete.addAll(
        noteExistingTasks.where((t) => !projectedTaskIds.contains(t.id)),
      );

      mergedNoteIds.add(noteId);
    }
  }

  return IsolateMergeResult(
    yjsStatesToInsert: yjsStatesToInsert,
    projectedNotes: projectedNotes,
    projectedTasks: projectedTasks,
    projectedCompletions: projectedCompletions,
    tasksToDelete: tasksToDelete,
    mergedNoteIds: mergedNoteIds,
  );
}

class ProjectedData {
  final NotesCompanion noteCompanion;
  final List<TasksCompanion> tasks;
  final List<LocalTaskCompletionsCompanion> completions;
  ProjectedData(this.noteCompanion, this.tasks, {this.completions = const []});
}

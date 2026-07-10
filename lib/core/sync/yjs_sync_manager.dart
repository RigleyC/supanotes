import 'dart:convert';
import 'dart:developer' as dev;

import 'package:drift/drift.dart';
import 'package:yjs_dart/yjs_dart.dart';

import '../../features/notes/domain/yjs_node_codec.dart';
import '../../features/tasks/domain/task_recurrence.dart';
import '../database/database.dart';

/// Manages a local Yjs [Doc] instance per note and persists binary
/// state snapshots to the [LocalYjsStates] Drift table.
///
/// Each note gets its own [Doc] instance. The binary state is loaded
/// from the local database on first access and flushed back on save.
class YjsSyncManager {
  YjsSyncManager({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  /// In-memory per-note Yjs documents.
  final Map<String, Doc> _docs = {};

  /// Load (or reconstruct) the canonical [Doc] for [noteId].
  ///
  /// Always reconstructs from [note_nodes] rather than calling [applyUpdate]
  /// on the persisted snapshot because `yjs_dart` v1.1.15 has a confirmed bug:
  /// [encodeStateAsUpdate] + [applyUpdate] deserialises YText types as YMap
  /// in the share map. The snapshot is still written by [persist] and used
  /// for server-side sync, but not for local Doc reconstruction.
  Future<Doc> loadDoc(String noteId) async {
    final cached = _docs[noteId];
    if (cached != null) return cached;

    final stateRow = await (_db.select(_db.localYjsStates)
          ..where((t) => t.noteId.equals(noteId)))
        .getSingleOrNull();
    if (stateRow != null) {
      final doc = Doc();
      final allNodes = await (_db.select(_db.noteNodes)
            ..where((t) => t.noteId.equals(noteId)))
          .get();

      for (final node in allNodes) {
        if (node.deletedAt == null) {
          doc.getText('content/${node.id}');
        }
      }
      try {
        applyUpdate(doc, stateRow.state);

        // Merge offline changes from SQLite into YDoc
        final nodesMap = doc.getMap('nodes')!;
        bool mutated = false;
        doc.transact((txn) {
          for (final node in allNodes) {
            if (node.deletedAt != null) {
              if (nodesMap.get(node.id) != null) {
                nodesMap.delete(node.id);
                final ytext = doc.getText('content/${node.id}')!;
                if (ytext.length > 0) {
                  ytext.delete(0, ytext.length);
                }
                mutated = true;
              }
              continue;
            }

            final rawMeta = nodesMap.get(node.id) as String?;
            final dbData = jsonDecode(node.data) as Map<String, dynamic>;
            final dbText = dbData['text'] as String? ?? '';
            final ytext = doc.getText('content/${node.id}')!;
            final ytextStr = ytext.toString();

            if (rawMeta == null || ytextStr != dbText) {
              final newMeta = {
                'id': node.id,
                'parentId': node.parentId,
                'position': node.position,
                'type': node.type,
                'data': dbData,
                'createdAt': node.createdAt.millisecondsSinceEpoch.toDouble(),
              };
              nodesMap.set(node.id, jsonEncode(newMeta));

              if (ytextStr != dbText) {
                if (ytext.length > 0) {
                  ytext.delete(0, ytext.length);
                }
                if (dbText.isNotEmpty) {
                  ytext.insert(0, dbText);
                }
              }
              mutated = true;
            }
          }
        });

        if (mutated) {
          await _db.into(_db.localYjsStates).insertOnConflictUpdate(
                LocalYjsStatesCompanion(
                  noteId: Value(noteId),
                  state: Value(encodeStateAsUpdate(doc)),
                ),
              );
        }

        _docs[noteId] = doc;
        dev.log('[YjsSyncManager] Loaded snapshot for note=$noteId', name: 'YjsSync');
        return doc;
      } catch (e) {
        dev.log('[YjsSyncManager] Failed to apply snapshot for note=$noteId: $e, reconstructing...', name: 'YjsSync');
      }
    }

    final doc = await _reconstructFromLocal(noteId);
    _docs[noteId] = doc;
    return doc;
  }

  Future<Doc> _reconstructFromLocal(String noteId) async {
    final doc = Doc();
    final nodes = await (_db.select(_db.noteNodes)
          ..where((t) => t.noteId.equals(noteId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.position)]))
        .get();

    for (final node in nodes) {
      final nodeId = node.id;
      Map<String, dynamic> dataMap = {};
      if (node.data.isNotEmpty) {
        try {
          dataMap = jsonDecode(node.data) as Map<String, dynamic>;
        } catch (_) {}
      }
      final textContent = dataMap['text'] as String? ?? '';

      final meta = <String, dynamic>{
        'id': nodeId,
        'parentId': node.parentId,
        'position': node.position,
        'type': node.type,
        'data': dataMap,
        'createdAt': node.createdAt.millisecondsSinceEpoch.toDouble(),
      };

      doc.getMap('nodes')!.set(nodeId, jsonEncode(meta));
      if (textContent.isNotEmpty) {
        doc.getText('content/$nodeId')!.insert(0, textContent);
      }
    }

    await _db.into(_db.localYjsStates).insertOnConflictUpdate(
          LocalYjsStatesCompanion(
            noteId: Value(noteId),
            state: Value(encodeStateAsUpdate(doc)),
          ),
        );
    dev.log('[YjsSyncManager] Reconstructed state for note=$noteId from ${nodes.length} nodes',
        name: 'YjsSync');
    return doc;
  }

  Future<void> _persistLock = Future.value();

  /// Persist the current in-memory Doc state for [noteId] to the database
  /// and project it to [note_nodes]. Unlike [applyUpdate], this does NOT call
  /// [applyUpdate] — it is safe to call when the Doc is already up-to-date
  /// (e.g. after the WS client applied a remote update).
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
              ),
            );
        await _projectToNodes(noteId, doc);
        dev.log('[YjsSyncManager] Persisted state for note=$noteId', name: 'YjsSync');
      } catch (e, stackTrace) {
        dev.log('YjsSyncManager persist error: $e', name: 'YjsSync', error: e, stackTrace: stackTrace, level: 1000);
      }
    });
    await _persistLock;
  }

  /// Project the in-memory [Doc] state into [note_nodes] so it survives
  /// reconstruction without calling [applyUpdate].
  Future<void> _projectToNodes(String noteId, Doc doc) async {
    final nodes = noteNodesFromDoc(doc, noteIdOverride: noteId);

    final activeIds = nodes.map((n) => n.id).toSet();
    final staleNodes = await (_db.select(_db.noteNodes)
          ..where((t) => t.noteId.equals(noteId) & t.deletedAt.isNull()))
        .get();

    final noteRow = await (_db.select(_db.notes)
          ..where((t) => t.id.equals(noteId)))
        .getSingleOrNull();
    final userId = noteRow?.userId ?? '';

    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await _db.batch((b) {
        for (final stale in staleNodes) {
          if (!activeIds.contains(stale.id)) {
            b.update(_db.noteNodes, NoteNodesCompanion(
              deletedAt: Value(now),
              updatedAt: Value(now),
            ), where: (t) => t.id.equals(stale.id));

            b.update(_db.tasks, TasksCompanion(
              deletedAt: Value(now),
              updatedAt: Value(now),
            ), where: (t) => t.id.equals(stale.id));
          }
        }
      });

      if (nodes.isNotEmpty) {
        await _db.batch((b) {
          for (final node in nodes) {
            b.insert(
              _db.noteNodes,
              node,
              onConflict: DoUpdate(
                (old) => NoteNodesCompanion(
                  parentId: Value(node.parentId),
                  position: Value(node.position),
                  type: Value(node.type),
                  data: Value(node.data),
                  updatedAt: Value(node.updatedAt),
                  deletedAt: const Value(null),
                ),
              ),
            );

            if (node.type == 'task') {
              Map<String, dynamic> dataMap = {};
              try {
                dataMap = jsonDecode(node.data) as Map<String, dynamic>;
              } catch (_) {}

              final completed = dataMap['completed'] == true || dataMap['isComplete'] == true;
              final dueDateStr = dataMap['dueDate'] as String?;
              final recurrenceStr = dataMap['recurrence'] as String?;

              DateTime? dueDate;
              if (dueDateStr != null && dueDateStr.isNotEmpty) {
                try {
                  dueDate = DateTime.parse(dueDateStr).toUtc();
                } catch (_) {}
              }

              final recurrence = TaskRecurrence.parse(recurrenceStr);

              final taskCompanion = TasksCompanion.insert(
                id: node.id,
                userId: userId,
                noteId: noteId,
                title: dataMap['text'] as String? ?? '',
                status: completed ? 'done' : 'open',
                position: Value(node.position),
                recurrence: Value(recurrence),
                dueDate: Value(dueDate),
                completedAt: Value(completed ? now : null),
                createdAt: node.createdAt,
                updatedAt: now,
                deletedAt: const Value(null),
                nodeId: Value(node.id),
              );

              b.insert(
                _db.tasks,
                taskCompanion,
                onConflict: DoUpdate(
                  (old) => TasksCompanion(
                    title: Value(dataMap['text'] as String? ?? ''),
                    status: Value(completed ? 'done' : 'open'),
                    position: Value(node.position),
                    recurrence: Value(recurrence),
                    dueDate: Value(dueDate),
                    completedAt: Value(completed ? now : null),
                    updatedAt: Value(now),
                    deletedAt: const Value(null),
                  ),
                ),
              );
            }
          }
        });
      }
    });
  }

  /// Dispose all in-memory Ydocs.
  void dispose() {
    _docs.clear();
  }
}

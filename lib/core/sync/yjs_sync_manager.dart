import 'dart:convert';
import 'dart:developer' as dev;

import 'package:drift/drift.dart';
import 'package:yjs_dart/yjs_dart.dart';

import '../../features/notes/domain/yjs_node_codec.dart';
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

    final tasks = await (_db.select(_db.tasks)
          ..where((t) => t.noteId.equals(noteId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.position)]))
        .get();

    for (final t in tasks) {
      final taskMeta = <String, dynamic>{
        'id': t.id,
        'noteId': noteId,
        'userId': t.userId,
        'title': t.title,
        'status': t.status,
        'position': t.position,
        'createdAt': t.createdAt.millisecondsSinceEpoch.toDouble(),
      };
      doc.getMap('tasks')!.set(t.id, jsonEncode(taskMeta));
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

  /// Persist the current in-memory Doc state for [noteId] to the database
  /// and project it to [note_nodes]. Unlike [applyUpdate], this does NOT call
  /// [applyUpdate] — it is safe to call when the Doc is already up-to-date
  /// (e.g. after the WS client applied a remote update).
  Future<void> persist(String noteId) async {
    final doc = _docs[noteId];
    if (doc == null) return;
    final state = encodeStateAsUpdate(doc);
    await _db.into(_db.localYjsStates).insertOnConflictUpdate(
          LocalYjsStatesCompanion(
            noteId: Value(noteId),
            state: Value(state),
          ),
        );
    await _projectToNodes(noteId, doc);
    dev.log('[YjsSyncManager] Persisted state for note=$noteId', name: 'YjsSync');
  }

  /// Project the in-memory [Doc] state into [note_nodes] so it survives
  /// reconstruction without calling [applyUpdate].
  Future<void> _projectToNodes(String noteId, Doc doc) async {
    final nodes = noteNodesFromDoc(doc, noteIdOverride: noteId);

    final activeIds = nodes.map((n) => n.id).toSet();
    final staleNodes = await (_db.select(_db.noteNodes)
          ..where((t) => t.noteId.equals(noteId) & t.deletedAt.isNull()))
        .get();
    final now = DateTime.now().toUtc();
    await _db.batch((b) {
      for (final stale in staleNodes) {
        if (!activeIds.contains(stale.id)) {
          b.update(_db.noteNodes, NoteNodesCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
          ), where: (t) => t.id.equals(stale.id));
        }
      }
    });

    if (nodes.isEmpty) return;

    await _db.batch((b) {
      for (final node in nodes) {
        b.insert(_db.noteNodes, node,
            onConflict: DoUpdate((_) => node));
      }
    });
  }

  /// Retrieve the in-memory [Doc] for [noteId].
  ///
  /// Throws a [StateError] if [loadDoc] has not been called first.
  Doc docFor(String noteId) {
    final d = _docs[noteId];
    if (d == null) {
      throw StateError('loadDoc($noteId) must be awaited before docFor');
    }
    return d;
  }

  /// Dispose all in-memory Ydocs.
  void dispose() {
    _docs.clear();
  }
}

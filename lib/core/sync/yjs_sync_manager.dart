import 'dart:convert';
import 'dart:developer' as dev;

import 'package:drift/drift.dart';
import 'package:yjs_dart/yjs_dart.dart';

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

  /// Per-note set of known node IDs for O(1) phantom-node checks.
  final Map<String, Set<String>> _nodeExistence = {};

  /// Load (or reconstruct) the canonical [Doc] for [noteId].
  ///
  /// Always reconstructs from [note_nodes] rather than calling [applyUpdate]
  /// on the persisted snapshot because `yjs_dart` v1.1.15 has a confirmed bug:
  /// [encodeStateAsUpdate] + [applyUpdate] deserialises YText types as YMap
  /// in the share map. The snapshot is still written by [saveState] and used
  /// for server-side sync, but not for local Doc reconstruction.
  Future<Doc> loadDoc(String noteId) async {
    final cached = _docs[noteId];
    if (cached != null) return cached;

    final doc = await _reconstructFromLocal(noteId);
    _docs[noteId] = doc;
    _updateNodeExistence(noteId, doc);
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

  /// Refresh [_nodeExistence] for [noteId] from the in-memory [Doc].
  void _updateNodeExistence(String noteId, Doc doc) {
    final nodes = doc.getMap('nodes');
    final ids = <String>{};
    if (nodes != null) {
      ids.addAll(nodes.keys);
    }
    _nodeExistence[noteId] = ids;
  }

  /// Apply [update] to the canonical [Doc] for [noteId] and persist the
  /// resulting binary state. The [update] payload MUST be a raw Yjs update
  /// (no transport prefix).
  ///
  /// Also projects the Doc state back into [note_nodes] so that
  /// [loadDoc] can reconstruct from the relational tables (bypassing
  /// `yjs_dart` v1.1.15's `applyUpdate` YText-corruption bug).
  Future<void> saveState(String noteId, Uint8List update) async {
    final doc = _docs[noteId] ?? await loadDoc(noteId);
    applyUpdate(doc, update);
    final state = encodeStateAsUpdate(doc);
    await _db.into(_db.localYjsStates).insertOnConflictUpdate(
          LocalYjsStatesCompanion(
            noteId: Value(noteId),
            state: Value(state),
          ),
        );
    await _projectToNodes(noteId, doc);
    _updateNodeExistence(noteId, doc);
    dev.log('[YjsSyncManager] Saved state for note=$noteId', name: 'YjsSync');
  }

  /// Project the in-memory [Doc] state into [note_nodes] so it survives
  /// reconstruction without calling [applyUpdate].
  Future<void> _projectToNodes(String noteId, Doc doc) async {
    final nodesMap = doc.getMap('nodes');
    if (nodesMap == null) return;
    final nodeIds = nodesMap.keys.toList();
    if (nodeIds.isEmpty) return;

    final now = DateTime.now().toUtc();
    await _db.batch((b) {
      for (final nodeId in nodeIds) {
        final raw = nodesMap.get(nodeId);
        if (raw is! String) continue;
        try {
          final meta = jsonDecode(raw) as Map<String, dynamic>;
          final ytext = doc.getText('content/$nodeId');
          final textContent = ytext?.toString() ?? '';
          final data = Map<String, dynamic>.from(meta['data'] as Map? ?? {});
          if (textContent.isNotEmpty) {
            data['text'] = textContent;
          }
          final rawParentId = meta['parentId'] as String?;
          final resolvedParentId =
              (rawParentId == null || rawParentId.isEmpty) ? null : rawParentId;
          final node = NoteNode(
            id: nodeId,
            noteId: noteId,
            parentId: resolvedParentId,
            position: (meta['position'] as num?)?.toDouble() ?? 0.0,
            type: meta['type'] as String? ?? 'paragraph',
            data: jsonEncode(data),
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              (meta['createdAt'] as num?)?.toInt() ??
                  now.millisecondsSinceEpoch,
            ),
            updatedAt: now,
            isDirty: false,
          );
          b.insert(_db.noteNodes, node,
              onConflict: DoUpdate((_) => node));
        } catch (_) {}
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

  /// Check whether [nodeId] exists inside the `nodes` YMap of the
  /// in-memory [Doc] for [noteId].
  ///
  /// This protects against phantom-node mutations where a remote peer
  /// has already deleted the node locally. Uses an in-memory set for
  /// O(1) lookup instead of decoding the binary state on every call.
  bool nodeExists(String noteId, String nodeId) {
    final ids = _nodeExistence[noteId];
    if (ids == null) return false;
    return ids.contains(nodeId);
  }

  /// Remove the in-memory doc for [noteId] to free resources.
  void unloadDoc(String noteId) {
    _docs.remove(noteId);
    _nodeExistence.remove(noteId);
  }

  /// Dispose all in-memory Ydocs.
  void dispose() {
    _docs.clear();
    _nodeExistence.clear();
  }
}

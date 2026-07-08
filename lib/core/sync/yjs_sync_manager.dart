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

  /// Load or recreate a Ydoc binary state for [noteId].
  ///
  /// If a snapshot exists in [LocalYjsStates] it is decoded into a fresh
  /// [Doc]; otherwise an empty document is returned.
  Future<Uint8List> loadState(String noteId) async {
    final row = await (_db.select(_db.localYjsStates)
      ..where((t) => t.noteId.equals(noteId))
    ).getSingleOrNull();

    if (row != null) {
      final doc = Doc();
      applyUpdate(doc, row.state);
      _docs[noteId] = doc;
      dev.log('[YjsSyncManager] Loaded state for note=$noteId', name: 'YjsSync');
      return row.state;
    }

    final doc = Doc();
    _docs[noteId] = doc;
    final emptyState = encodeStateAsUpdate(doc);
    dev.log('[YjsSyncManager] Created empty state for note=$noteId', name: 'YjsSync');
    return emptyState;
  }

  /// Persist the current Ydoc state of [noteId] to the local database.
  Future<void> saveState(String noteId, Uint8List state) async {
    await _db.into(_db.localYjsStates).insertOnConflictUpdate(
      LocalYjsStatesCompanion(
        noteId: Value(noteId),
        state: Value(state),
      ),
    );
    dev.log('[YjsSyncManager] Saved state for note=$noteId', name: 'YjsSync');
  }

  /// Retrieve the in-memory [Doc] for [noteId], loading from the DB
  /// on first access.
  Doc docFor(String noteId) {
    if (_docs.containsKey(noteId)) return _docs[noteId]!;
    final doc = Doc();
    _docs[noteId] = doc;
    return doc;
  }

  /// Check whether [nodeId] exists inside the `nodes` YMap of the
  /// given [state].
  ///
  /// This protects against phantom-node mutations where a remote peer
  /// has already deleted the node locally.
  bool nodeExists(Uint8List state, String nodeId) {
    final doc = Doc();
    applyUpdate(doc, state);
    final nodes = doc.getMap('nodes');
    return nodes?.get(nodeId) != null;
  }

  /// Remove the in-memory doc for [noteId] to free resources.
  void unloadDoc(String noteId) {
    _docs.remove(noteId);
  }

  /// Dispose all in-memory Ydocs.
  void dispose() {
    _docs.clear();
  }
}

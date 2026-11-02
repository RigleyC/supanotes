import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:dart_quill_delta/dart_quill_delta.dart' as quill;
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_codec.dart';
import 'package:supanotes/features/notes/editor/document/note_blocks.dart';
import 'package:supanotes/features/notes/editor/sync/note_document_adapter.dart';
import 'package:supanotes/features/notes/editor/sync/note_operation_contract.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';
import 'package:uuid/uuid.dart';

/// Connects an AppFlowy [EditorState] to the note's REST/OT sync.
///
/// Local edits arrive as editor transactions. The adapter keeps a mirror of
/// the document as synced blocks, re-reads only the nodes a transaction
/// touched (the whole tree only when blocks are inserted or removed), diffs
/// the mirror into REST/OT operations and persists them to the outbox.
/// Server results are applied back as remote transactions, which AppFlowy
/// neither records in undo history nor reports as local edits.
final class AppFlowyNoteAdapter implements NoteDocumentAdapter {
  AppFlowyNoteAdapter({
    required this.editorState,
    required NoteOperationsSyncService syncService,
    required String noteId,
    bool captureLocalOperations = true,
    NoteAppFlowyCodec codec = const NoteAppFlowyCodec(),
  }) : _syncService = syncService,
       _noteId = noteId,
       _captureLocalOperations = captureLocalOperations,
       _codec = codec;

  final EditorState editorState;
  final NoteOperationsSyncService _syncService;
  final String _noteId;
  final NoteAppFlowyCodec _codec;
  bool _captureLocalOperations;

  static const _opsFlushDelay = Duration(milliseconds: 50);

  /// The materialized document is a projection of the same edits carried by
  /// the operations, so it is written on a slower debounce and on flush.
  static const _materializedSaveDelay = Duration(milliseconds: 1200);

  static const _uuid = Uuid();

  @override
  void Function(List<OperationRequest> ops)? onLocalOperations;

  List<NoteBlock> _mirror = const [];
  final List<OperationRequest> _pendingOps = [];
  StreamSubscription<EditorTransactionValue>? _transactions;
  Timer? _flushTimer;
  Timer? _materializedTimer;
  bool _materializedDirty = false;
  bool _disposed = false;
  int _confirmedRevision = 0;
  Future<void> _flushTail = Future<void>.value();

  /// Ids assigned to nodes the editor created (Enter, paste) until the id is
  /// written into the node, so repeated reads agree on one identity.
  final Expando<String> _assignedIds = Expando<String>();

  int get confirmedRevision => _confirmedRevision;

  /// The document as synced blocks, as last captured or applied.
  List<NoteBlock> get blocks => _mirror;

  @override
  Future<void> start() async {
    if (_disposed) return;
    final confirmed = await _syncService.getConfirmedDocument(_noteId);
    final pending = await _syncService.getPendingOperations(_noteId);
    if (_disposed) return;
    if (confirmed != null) _confirmedRevision = confirmed.revision;

    if (confirmed != null || pending.isNotEmpty) {
      final snapshot = confirmed == null
          ? const <String, dynamic>{'blocks': <dynamic>[]}
          : jsonDecode(confirmed.documentJson) as Map<String, dynamic>;
      await _replaceDocument(
        projectNoteBlocks(snapshot: snapshot, pendingOps: pending),
      );
    }
    _mirror = _readDocument();
    if (_disposed) return;
    await _syncService.storeMaterializedDocument(
      noteId: _noteId,
      documentJson: _encode(_mirror),
    );
    _transactions = editorState.transactionStream.listen(_onTransaction);
  }

  @override
  void setCaptureLocalOperations(bool captureLocalOperations) {
    if (_disposed) return;
    _captureLocalOperations = captureLocalOperations;
    // Read-only sessions still receive remote changes; keep the mirror in
    // step with whatever the editor shows when capture resumes.
    if (captureLocalOperations) _mirror = _readDocument();
  }

  void _onTransaction(EditorTransactionValue value) {
    final (time, transaction, _) = value;
    if (_disposed || time != TransactionTime.after) return;
    if (!_captureLocalOperations) return;

    final before = _mirror;
    final after = _readAfter(transaction, before);
    _mirror = after;
    final operations = diffNoteBlocks(before, after);
    if (operations.isEmpty) return;
    _stampAssignedIds();

    final requests = <OperationRequest>[];
    for (final operation in operations) {
      final error = NoteOperationContract.validate(
        kind: operation.kind,
        blockId: operation.blockId,
        payload: operation.payload,
      );
      if (error != null) {
        throw StateError('Captured invalid note operation: $error');
      }
      requests.add(
        OperationRequest(
          operationId: _syncService.generateOperationId(),
          baseRevision: _confirmedRevision,
          kind: operation.kind,
          blockId: operation.blockId,
          payload: operation.payload,
        ),
      );
    }
    _pendingOps.addAll(requests);
    _scheduleFlush();
    _scheduleMaterializedSave();
  }

  /// Re-reads the blocks a transaction changed. Text and attribute updates
  /// touch known nodes, so only those are converted; inserts and deletes
  /// change the shape and re-read the whole tree.
  List<NoteBlock> _readAfter(Transaction transaction, List<NoteBlock> before) {
    final touched = <Node>{};
    for (final operation in transaction.operations) {
      if (operation is InsertOperation || operation is DeleteOperation) {
        return _readDocument();
      }
      final node = editorState.getNodeAtPath(operation.path);
      if (node == null) return _readDocument();
      touched.add(node);
    }
    if (touched.isEmpty) return before;

    final indexById = {
      for (var i = 0; i < before.length; i++) before[i].id: i,
    };
    final updated = List<NoteBlock>.of(before);
    for (final node in touched) {
      final id = node.attributes[NoteNodeKeys.blockId] as String?;
      final index = id == null ? null : indexById[id];
      if (index == null) return _readDocument();
      updated[index] = _codec.toBlock(
        node,
        id: id!,
        depth: node.path.length - 1,
      );
    }
    return updated;
  }

  List<NoteBlock> _readDocument() => _codec.toBlocks(
    editorState.document,
    idFor: (node) => _assignedIds[node] ??= _uuid.v4(),
  );

  /// Writes ids assigned during capture into their nodes, outside the
  /// transaction being observed and without recording undo history.
  void _stampAssignedIds() {
    final unstamped = <(Node, String)>[];
    void visit(Node node) {
      final assigned = _assignedIds[node];
      if (assigned != null &&
          node.attributes[NoteNodeKeys.blockId] != assigned) {
        unstamped.add((node, assigned));
      }
      node.children.forEach(visit);
    }

    editorState.document.root.children.forEach(visit);
    if (unstamped.isEmpty) return;
    scheduleMicrotask(() {
      if (_disposed) return;
      final transaction = editorState.transaction;
      for (final (node, id) in unstamped) {
        if (node.parent == null) continue;
        transaction.updateNode(node, {NoteNodeKeys.blockId: id});
      }
      if (transaction.operations.isEmpty) return;
      unawaited(
        editorState.apply(
          transaction,
          isRemote: true,
          skipEditableCheck: true,
          withUpdateSelection: false,
        ),
      );
    });
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(_opsFlushDelay, () {
      if (_disposed) return;
      unawaited(_queueFlush(propagateErrors: false));
    });
  }

  void _scheduleMaterializedSave() {
    _materializedDirty = true;
    _materializedTimer?.cancel();
    _materializedTimer = Timer(_materializedSaveDelay, () {
      _materializedTimer = null;
      unawaited(
        _saveMaterialized().catchError((Object error, StackTrace stack) {
          dev.log(
            'Materialized document save failed for $_noteId',
            error: error,
            stackTrace: stack,
          );
        }),
      );
    });
  }

  Future<void> _saveMaterialized() async {
    if (_disposed || !_materializedDirty) return;
    _materializedTimer?.cancel();
    _materializedTimer = null;
    _materializedDirty = false;
    try {
      await _syncService.storeMaterializedDocument(
        noteId: _noteId,
        documentJson: _encode(_mirror),
      );
    } catch (_) {
      _materializedDirty = true;
      rethrow;
    }
  }

  Future<void> _queueFlush({required bool propagateErrors}) {
    final flush = _flushTail.then<void>((_) => _flushLocalOps());
    _flushTail = flush.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        dev.log(
          'Local operation flush failed for $_noteId; keeping them in memory',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
    return propagateErrors ? flush : _flushTail;
  }

  Future<void> _flushLocalOps() async {
    if (_pendingOps.isEmpty) return;
    final ops = List<OperationRequest>.of(_pendingOps);
    _pendingOps.clear();
    try {
      await _syncService.enqueueOperations(_noteId, ops);
    } catch (error, stackTrace) {
      _pendingOps.insertAll(0, ops);
      Error.throwWithStackTrace(error, stackTrace);
    }
    onLocalOperations?.call(ops);
  }

  @override
  Future<void> flushNow() async {
    _flushTimer?.cancel();
    while (true) {
      await _queueFlush(propagateErrors: true);
      if (_pendingOps.isEmpty) break;
    }
    await _saveMaterialized();
  }

  @override
  Future<void> reconcile(SyncResult result) async {
    if (_disposed) return;
    final canonical = result.canonicalDocument;
    if (canonical == null) return;
    _confirmedRevision = result.finalRevision;
    await flushNow();
    if (_disposed) return;
    final rebased = await _syncService.getPendingOperations(_noteId);
    if (_disposed) return;
    if (result.remoteOperations.isEmpty && rebased.isEmpty) return;
    await rebuildFromSnapshot(
      snapshot: canonical.document,
      pendingOps: _withInMemoryOps(rebased),
    );
  }

  /// Shows [snapshot] plus [pendingOps] in the editor, changing only the
  /// blocks that differ from what it shows now.
  Future<void> rebuildFromSnapshot({
    required Map<String, dynamic> snapshot,
    required List<PendingNoteOperationData>? pendingOps,
  }) async {
    if (_disposed) return;
    final target = projectNoteBlocks(
      snapshot: snapshot,
      pendingOps: pendingOps,
    );
    await _replaceDocument(target);
    _mirror = _readDocument();
    await _syncService.storeMaterializedDocument(
      noteId: _noteId,
      documentJson: _encode(_mirror),
    );
  }

  /// Makes the editor show [target]. When only block contents changed, the
  /// affected nodes are updated in place so the caret, focus and widgets of
  /// untouched blocks survive; any change in shape rebuilds the tree once.
  Future<void> _replaceDocument(List<NoteBlock> target) async {
    final current = _readDocument();
    if (_sameShape(current, target)) {
      final transaction = editorState.transaction;
      Selection? selection = editorState.selection;
      for (var i = 0; i < target.length; i++) {
        if (current[i] == target[i]) continue;
        final node = _nodeForBlock(target[i].id);
        if (node == null) continue;
        final replacement = _codec.toNode(target[i]);
        transaction.updateNode(node, {
          ...replacement.attributes,
          if (!replacement.attributes.containsKey(NoteNodeKeys.metadata))
            NoteNodeKeys.metadata: null,
        });
        selection = _shiftSelection(selection, node, current[i], target[i]);
      }
      if (transaction.operations.isEmpty) return;
      await editorState.apply(
        transaction,
        isRemote: true,
        skipEditableCheck: true,
      );
      // Remote application computes its own selection; put back the caret
      // shifted past remote text inserted before it.
      _restoreSelection(selection);
      return;
    }

    // Shape changed: replace all top-level nodes in one transaction and put
    // the caret back in the same block when it still exists.
    final selection = editorState.selection;
    final caretBlock = selection == null
        ? null
        : editorState
                  .getNodeAtPath(selection.end.path)
                  ?.attributes[NoteNodeKeys.blockId]
              as String?;
    final caretOffset = selection?.end.offset ?? 0;
    final next = _codec.toDocument(target);
    final nodes = next.root.children.map((node) => node.deepCopy()).toList();
    // Insert before deleting: a transaction rebases later operations on
    // earlier ones, so deleting first would shift the insert path to -1 and
    // reverse the order of the new nodes.
    final transaction = editorState.transaction
      ..insertNodes([0], nodes, deepCopy: false)
      ..deleteNodes(editorState.document.root.children.toList());
    await editorState.apply(
      transaction,
      isRemote: true,
      skipEditableCheck: true,
    );
    final node = caretBlock == null ? null : _nodeForBlock(caretBlock);
    _restoreSelection(
      node == null
          ? null
          : Selection.collapsed(
              Position(
                path: node.path,
                offset: caretOffset.clamp(0, node.delta?.length ?? 0),
              ),
            ),
    );
  }

  void _restoreSelection(Selection? selection) {
    if (_disposed || selection == null) return;
    editorState.updateSelectionWithReason(
      selection,
      reason: SelectionUpdateReason.remote,
    );
  }

  bool _sameShape(List<NoteBlock> a, List<NoteBlock> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].type != b[i].type ||
          a[i].indent != b[i].indent) {
        return false;
      }
    }
    return true;
  }

  Node? _nodeForBlock(String blockId) {
    Node? found;
    void visit(Node node) {
      if (found != null) return;
      if (node.attributes[NoteNodeKeys.blockId] == blockId) {
        found = node;
        return;
      }
      node.children.forEach(visit);
    }

    editorState.document.root.children.forEach(visit);
    return found;
  }

  /// Moves a caret inside [node] past text that a remote change inserted
  /// before it, so the local user keeps typing where they were.
  Selection? _shiftSelection(
    Selection? selection,
    Node node,
    NoteBlock before,
    NoteBlock after,
  ) {
    if (selection == null) return null;
    final change = diffBlockDelta(before.delta, after.delta);
    if (change.isEmpty) return selection;
    final delta = quill.Delta.fromJson(change);
    Position shift(Position position) => position.path.equals(node.path)
        ? Position(
            path: position.path,
            offset: delta.transformPosition(position.offset, force: false),
          )
        : position;
    return Selection(start: shift(selection.start), end: shift(selection.end));
  }

  List<PendingNoteOperationData> _withInMemoryOps(
    List<PendingNoteOperationData> persisted,
  ) {
    if (_pendingOps.isEmpty) return persisted;
    var ordinal = persisted.isEmpty ? 0 : persisted.last.ordinal + 1;
    return [
      ...persisted,
      for (final op in _pendingOps)
        PendingNoteOperationData(
          operationId: op.operationId,
          noteId: _noteId,
          baseRevision: op.baseRevision,
          ordinal: ordinal++,
          kind: op.kind,
          blockId: op.blockId,
          payloadJson: jsonEncode(op.payload),
          createdAt: DateTime.now().toUtc(),
          attemptCount: 0,
          status: '',
        ),
    ];
  }

  String _encode(List<NoteBlock> blocks) =>
      jsonEncode(noteSnapshotFromBlocks(blocks));

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _flushTimer?.cancel();
    _materializedTimer?.cancel();
    unawaited(_transactions?.cancel());
  }
}

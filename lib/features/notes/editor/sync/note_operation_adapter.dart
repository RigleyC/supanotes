import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/debug/note_sync_debug.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/notes/editor/document/document_projection_applier.dart';
import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';
import 'package:supanotes/features/notes/editor/sync/editor_operation_capture.dart';
import 'package:supanotes/features/notes/editor/sync/note_operation_contract.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';
import 'package:super_editor/super_editor.dart';

class _RebuildRequest {
  _RebuildRequest({required this.snapshot, this.ops});
  final Map<String, dynamic> snapshot;
  final List<PendingNoteOperationData>? ops;
}

class NoteOperationAdapter {
  NoteOperationAdapter({
    required MutableDocument document,
    required NoteOperationsSyncService syncService,
    required String noteId,
    required Editor editor,
    bool captureLocalOperations = true,
    NoteDocumentCodec codec = const NoteDocumentCodec(),
  }) : _syncService = syncService,
       _noteId = noteId,
       _document = document,
       _editor = editor,
       _captureLocalOperations = captureLocalOperations,
       _codec = codec {
    _applier = DocumentProjectionApplier(
      document: document,
      editor: editor,
      codec: _codec,
    );
    _capture = EditorOperationCapture(
      document: document,
      generateOpId: _syncService.generateOperationId,
      codec: _codec,
      onOperationsCaptured: _onOperationsCaptured,
    );
    // The composer is the source of truth for IME composition in this
    // super_editor version. A deferred rebuild is flushed as soon as the
    // platform commits (or cancels) the composition.
    _editor.maybeComposer?.composingRegion.addListener(
      _onComposingRegionChanged,
    );
  }

  final NoteOperationsSyncService _syncService;
  final String _noteId;
  final MutableDocument _document;
  final Editor _editor;
  bool _captureLocalOperations;
  final NoteDocumentCodec _codec;

  late final DocumentProjectionApplier _applier;
  late final EditorOperationCapture _capture;

  int _confirmedRevision = 0;
  LocalNoteDocumentData? _confirmedDocument;
  final List<OperationRequest> _pendingOps = [];
  Timer? _debounceTimer;
  Timer? _materializedTimer;
  bool _materializedDirty = false;

  static const _opsFlushDelay = Duration(milliseconds: 50);

  /// The materialized document is a projection of the same edits carried by
  /// the operations. Encoding and writing the whole document on every 50 ms
  /// batch would serialize it several times per typed word, so it follows its
  /// own slower debounce and is force-saved by [flushNow].
  static const _materializedSaveDelay = Duration(milliseconds: 1200);

  int get confirmedRevision => _confirmedRevision;
  bool get captureLocalOperations => _captureLocalOperations;
  bool get hasCapturedLocalOperations => _hasCapturedLocalOperations;

  void Function(List<OperationRequest> ops)? onLocalOperations;

  bool _disposed = false;
  bool _hasCapturedLocalOperations = false;
  _RebuildRequest? _pendingRebuild;

  /// Whether the platform IME is mid-composition in the editor.
  ///
  /// Composition state lives on the composer (`composer.composingRegion`),
  /// not on the text: this super_editor version never writes a 'composing'
  /// text attribution, so any guard based on attributions or on manually
  /// forwarded start/end calls is dead code and never protects typing.
  bool get _isEditorComposing {
    final composer = _editor.maybeComposer;
    return composer != null && composer.composingRegion.value != null;
  }

  void _onComposingRegionChanged() {
    if (_disposed || _pendingRebuild == null) return;
    if (_isEditorComposing) return;
    // Flush on a microtask so the deferred rebuild never mutates the document
    // re-entrantly inside the edit that ended the composition. Capture runs
    // synchronously on that document change, so by flush time the committed
    // operations are already merged into the projection.
    scheduleMicrotask(_flushDeferredRebuild);
  }

  void _flushDeferredRebuild() {
    if (_disposed) return;
    final request = _pendingRebuild;
    if (request == null) return;
    if (_isEditorComposing) return; // composition restarted; wait again
    _pendingRebuild = null;
    unawaited(
      rebuildFromSnapshot(snapshot: request.snapshot, rebasedOps: request.ops),
    );
  }

  Future<void> start() async {
    if (_disposed) return;
    _capture.setSuppress(true);
    _capture.buildMirror();
    await _loadConfirmedState();
    if (_disposed) return;
    if (_captureLocalOperations) {
      _capture.start();
    }
    await _hydrateFromPersistedState();
    if (_disposed) return;
    await _syncService.storeMaterializedDocument(
      noteId: _noteId,
      documentJson: _encodeCurrentDocument(),
    );
    _capture.buildMirror();
    _capture.setSuppress(!_captureLocalOperations);
  }

  void setCaptureLocalOperations(bool captureLocalOperations) {
    if (_disposed || _captureLocalOperations == captureLocalOperations) return;
    _captureLocalOperations = captureLocalOperations;
    _capture.setSuppress(!captureLocalOperations);
    if (captureLocalOperations) {
      _capture.start();
      return;
    }
    _capture.stop();
    _capture.buildMirror();
  }

  Future<void> _loadConfirmedState() async {
    final doc = await _syncService.getConfirmedDocument(_noteId);
    _confirmedDocument = doc;
    if (doc != null) {
      _confirmedRevision = doc.revision;
    }
  }

  Future<void> _hydrateFromPersistedState() async {
    try {
      final doc = _confirmedDocument;
      final pending = await _syncService.getPendingOperations(_noteId);
      if (_disposed) return;
      if (doc == null && pending.isEmpty) return;
      if (doc == null && !_codec.isEmptyDocumentPlaceholder(_document)) {
        return;
      }

      final snapshot = doc == null
          ? const <String, dynamic>{'blocks': <dynamic>[]}
          : jsonDecode(doc.documentJson) as Map<String, dynamic>;
      await _applier.rebuildFromSnapshot(
        snapshot: snapshot,
        pendingOps: pending,
        repairPersistedSnapshot: true,
        suppressCapture: () => _capture.setSuppress(true),
        resumeCapture: () => _capture.setSuppress(!_captureLocalOperations),
        rebuildMirror: _capture.buildMirror,
      );
      if (_disposed) return;
      if (doc != null) {
        _confirmedRevision = doc.revision;
      }
    } catch (e, stackTrace) {
      dev.log(
        'Hydration from persisted state failed for note $_noteId',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  void _onOperationsCaptured(List<OperationRequestData> requests) {
    if (_disposed) return;
    if (kDebugMode) {
      NoteSyncDebug.log(
        'adapter.captured',
        noteId: _noteId,
        fields: {
          'confirmedRevision': _confirmedRevision,
          'count': requests.length,
          'operations': requests
              .map(
                (request) =>
                    '${request.operationId}:${request.kind}:${request.blockId}',
              )
              .join('|'),
        },
      );
    }
    for (final req in requests) {
      final contractError = NoteOperationContract.validate(
        kind: req.kind,
        blockId: req.blockId,
        payload: req.payload,
      );
      if (contractError != null) {
        throw StateError(
          'Captured invalid note operation ${req.operationId}: '
          '$contractError',
        );
      }
    }
    for (final req in requests) {
      _pendingOps.add(
        OperationRequest(
          operationId: req.operationId,
          baseRevision: _confirmedRevision,
          kind: req.kind,
          blockId: req.blockId,
          payload: req.payload,
        ),
      );
    }
    if (requests.isNotEmpty) {
      _hasCapturedLocalOperations = true;
    }
    _scheduleDebounceFlush();
    _scheduleMaterializedSave();
  }

  void _scheduleDebounceFlush() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_opsFlushDelay, () {
      if (_disposed) return;
      unawaited(_queueFlush(propagateErrors: false));
    });
  }

  void _scheduleMaterializedSave() {
    if (_disposed) return;
    _materializedDirty = true;
    _materializedTimer?.cancel();
    _materializedTimer = Timer(_materializedSaveDelay, () {
      _materializedTimer = null;
      unawaited(_saveMaterializedDocumentSafely());
    });
  }

  Future<void> _saveMaterializedDocumentSafely() async {
    try {
      await _saveMaterializedDocument();
    } on Object catch (_) {
      // Already reported. The next edit or explicit flush retries the write.
    }
  }

  Future<void> _saveMaterializedDocument() async {
    if (_disposed || !_materializedDirty) return;
    _materializedTimer?.cancel();
    _materializedTimer = null;
    _materializedDirty = false;
    try {
      await _syncService.storeMaterializedDocument(
        noteId: _noteId,
        documentJson: _encodeCurrentDocument(),
      );
    } catch (error, stackTrace) {
      _materializedDirty = true;
      dev.log(
        'Materialized document save failed for $_noteId',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> _flushTail = Future<void>.value();

  Future<void> _queueFlush({required bool propagateErrors}) {
    final flush = _flushTail.then<void>((_) => _flushLocalOps());
    _flushTail = flush.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        dev.log(
          'Local operation flush failed for $_noteId; '
          'keeping operations in memory',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
    return propagateErrors ? flush : _flushTail;
  }

  Future<void> _flushLocalOps() async {
    if (_pendingOps.isEmpty) return;
    final ops = List<OperationRequest>.from(_pendingOps);
    _pendingOps.clear();
    var persisted = false;
    try {
      if (kDebugMode) {
        NoteSyncDebug.log(
          'adapter.flush.begin',
          noteId: _noteId,
          fields: {
            'confirmedRevision': _confirmedRevision,
            'operationCount': ops.length,
          },
        );
        for (final op in ops) {
          NoteSyncDebug.log(
            'adapter.flush.enqueue',
            noteId: _noteId,
            fields: {
              'operationId': op.operationId,
              'baseRevision': op.baseRevision,
              'kind': op.kind,
              'blockId': op.blockId,
              'payload': NoteSyncDebug.payloadSummary(op.payload),
            },
          );
        }
      }

      // Operations are the durable record of the edit. The materialized
      // document is written by its own slower debounce, so this hot path does
      // not encode the whole document on every keystroke batch.
      await _syncService.enqueueOperations(_noteId, ops);
      persisted = true;

      onLocalOperations?.call(ops);
    } catch (error, stackTrace) {
      if (!persisted) {
        _pendingOps.insertAll(0, ops);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  String _encodeCurrentDocument() {
    return jsonEncode({
      'schemaVersion': 1,
      'blocks': _codec.encodeDocument(_document),
    });
  }

  Future<void> flushNow() async {
    _debounceTimer?.cancel();
    while (true) {
      await _queueFlush(propagateErrors: true);
      if (_pendingOps.isEmpty) break;
    }
    await _saveMaterializedDocument();
  }

  Future<void> reconcile(SyncResult result) async {
    if (_disposed) return;
    final canonical = result.canonicalDocument;
    if (canonical == null) return;
    _confirmedRevision = result.finalRevision;
    await flushNow();
    if (_disposed) return;
    final rebasedOps = await _syncService.getPendingOperations(_noteId);
    if (_disposed) return;
    if (kDebugMode) {
      NoteSyncDebug.log(
        'adapter.reconcile',
        noteId: _noteId,
        fields: {
          'revision': result.finalRevision,
          'accepted': result.acceptedCount,
          'remoteOperations': result.remoteOperations.length,
          'rebasedOperations': rebasedOps.length,
          'canonical': NoteSyncDebug.documentSummary(canonical.document),
        },
      );
    }

    if (result.remoteOperations.isEmpty && rebasedOps.isEmpty) {
      if (kDebugMode) {
        NoteSyncDebug.log(
          'adapter.reconcile.skip_local_ack',
          noteId: _noteId,
          fields: {'rebasedOperations': rebasedOps.length},
        );
      }
      return;
    }

    await rebuildFromSnapshot(
      snapshot: canonical.document,
      rebasedOps: rebasedOps,
    );
  }

  List<PendingNoteOperationData> _mergeInMemoryOps(
    List<PendingNoteOperationData> persisted,
  ) {
    if (_pendingOps.isEmpty) return persisted;
    final merged = List<PendingNoteOperationData>.from(persisted);
    final startOrdinal = persisted.isEmpty ? 0 : persisted.last.ordinal + 1;
    var ordinal = startOrdinal;
    for (final op in _pendingOps) {
      merged.add(
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
      );
    }
    return merged;
  }

  Future<void> rebuildFromSnapshot({
    required Map<String, dynamic> snapshot,
    required List<PendingNoteOperationData>? rebasedOps,
  }) async {
    if (_disposed) return;
    if (_isEditorComposing) {
      NoteSyncDebug.log('adapter.rebuild.deferred_composing', noteId: _noteId);
      _pendingRebuild = _RebuildRequest(snapshot: snapshot, ops: rebasedOps);
      return;
    }
    if (rebasedOps != null) {
      rebasedOps = _mergeInMemoryOps(rebasedOps);
    }

    if (kDebugMode) {
      NoteSyncDebug.log(
        'adapter.rebuild.begin',
        noteId: _noteId,
        fields: {
          'pendingOperations': rebasedOps?.length ?? 0,
          'snapshot': NoteSyncDebug.documentSummary(snapshot),
        },
      );
    }

    await _applier.rebuildFromSnapshot(
      snapshot: snapshot,
      pendingOps: rebasedOps,
      repairPersistedSnapshot: false,
      suppressCapture: () => _capture.setSuppress(true),
      resumeCapture: () => _capture.setSuppress(false),
      rebuildMirror: () => _capture.buildMirror(),
    );
    await _syncService.storeMaterializedDocument(
      noteId: _noteId,
      documentJson: _encodeCurrentDocument(),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _debounceTimer?.cancel();
    _materializedTimer?.cancel();
    _pendingRebuild = null;
    _editor.maybeComposer?.composingRegion.removeListener(
      _onComposingRegionChanged,
    );
    _capture.stop();
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/debug/note_sync_debug.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';
import 'package:supanotes/features/notes/editor/document/document_projection_applier.dart';
import 'package:supanotes/features/notes/editor/sync/note_operation_contract.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';

import 'editor_operation_capture.dart';

class _RebuildRequest {
  final Map<String, dynamic> snapshot;
  final List<PendingNoteOperationData>? ops;
  _RebuildRequest({required this.snapshot, this.ops});
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
       _captureLocalOperations = captureLocalOperations,
       _codec = codec {
    _applier = DocumentProjectionApplier(
      document: document,
      editor: editor,
      codec: _codec,
    );
    _capture = EditorOperationCapture(
      document: document,
      generateOpId: () => _syncService.generateOperationId(),
      codec: _codec,
      onOperationsCaptured: _onOperationsCaptured,
    );
  }

  final NoteOperationsSyncService _syncService;
  final String _noteId;
  final MutableDocument _document;
  bool _captureLocalOperations;
  final NoteDocumentCodec _codec;

  late final DocumentProjectionApplier _applier;
  late final EditorOperationCapture _capture;

  int _confirmedRevision = 0;
  LocalNoteDocumentData? _confirmedDocument;
  final List<OperationRequest> _pendingOps = [];
  Timer? _debounceTimer;

  final StreamController<List<PendingNoteOperationData>> _pendingOpsController =
      StreamController<List<PendingNoteOperationData>>.broadcast();

  Stream<List<PendingNoteOperationData>> get pendingOperationsStream =>
      _pendingOpsController.stream;

  int get confirmedRevision => _confirmedRevision;
  bool get captureLocalOperations => _captureLocalOperations;
  bool get hasCapturedLocalOperations => _hasCapturedLocalOperations;

  void Function(List<OperationRequest> ops)? onLocalOperations;

  bool _isComposing = false;
  bool _disposed = false;
  bool _hasCapturedLocalOperations = false;
  _RebuildRequest? _pendingRebuild;

  void onCompositionStart() {
    if (!_disposed) _isComposing = true;
  }

  void onCompositionEnd() {
    if (_disposed) return;
    _isComposing = false;
    if (_pendingRebuild != null) {
      final req = _pendingRebuild!;
      _pendingRebuild = null;
      unawaited(
        rebuildFromSnapshot(snapshot: req.snapshot, rebasedOps: req.ops),
      );
    }
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
      final pending = await _syncService.loadPendingProjection(_noteId);
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
  }

  void _scheduleDebounceFlush() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 50), () {
      if (_disposed) return;
      unawaited(_queueFlush(propagateErrors: false));
    });
  }

  Future<void> _flushTail = Future<void>.value();

  Future<void> _queueFlush({required bool propagateErrors}) {
    final flush = _flushTail.then<void>((_) => _flushLocalOps());
    _flushTail = flush.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        dev.log(
          'Local operation flush failed for $_noteId; keeping operations in memory',
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

      await _syncService.enqueueOperations(_noteId, ops);
      persisted = true;

      onLocalOperations?.call(ops);
      final pending = await _syncService.getPendingOperations(_noteId);
      _pendingOpsController.add(pending);
    } catch (error, stackTrace) {
      if (!persisted) {
        _pendingOps.insertAll(0, ops);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> flushNow() async {
    _debounceTimer?.cancel();
    while (true) {
      await _queueFlush(propagateErrors: true);
      if (_pendingOps.isEmpty) return;
    }
  }

  Future<void> reconcile(SyncResult result) async {
    if (_disposed) return;
    final canonical = result.canonicalDocument;
    if (canonical == null) return;
    _confirmedRevision = result.finalRevision;
    await flushNow();
    if (_disposed) return;
    final rebasedOps = await _syncService.loadPendingProjection(_noteId);
    if (_disposed) return;
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

    if (result.remoteOperations.isEmpty) {
      NoteSyncDebug.log(
        'adapter.reconcile.skip_local_ack',
        noteId: _noteId,
        fields: {'rebasedOperations': rebasedOps.length},
      );
      return;
    }

    await rebuildFromSnapshot(
      snapshot: canonical.document,
      rebasedOps: rebasedOps,
    );
  }

  Future<void> rebuildFromSnapshot({
    required Map<String, dynamic> snapshot,
    required List<PendingNoteOperationData>? rebasedOps,
  }) async {
    if (_disposed) return;
    if (_isComposing) {
      NoteSyncDebug.log('adapter.rebuild.deferred_composing', noteId: _noteId);
      _pendingRebuild = _RebuildRequest(snapshot: snapshot, ops: rebasedOps);
      return;
    }

    NoteSyncDebug.log(
      'adapter.rebuild.begin',
      noteId: _noteId,
      fields: {
        'pendingOperations': rebasedOps?.length ?? 0,
        'snapshot': NoteSyncDebug.documentSummary(snapshot),
      },
    );

    await _applier.rebuildFromSnapshot(
      snapshot: snapshot,
      pendingOps: rebasedOps,
      suppressCapture: () => _capture.setSuppress(true),
      resumeCapture: () => _capture.setSuppress(false),
      rebuildMirror: () => _capture.buildMirror(),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _debounceTimer?.cancel();
    _pendingRebuild = null;
    _capture.stop();
    _pendingOpsController.close();
  }
}

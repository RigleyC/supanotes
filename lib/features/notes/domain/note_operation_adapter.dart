import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/debug/note_sync_debug.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/notes/data/note_operations_api.dart';
import 'document_projection_applier.dart';
import 'editor_operation_capture.dart';
import 'ot_document_codec.dart';

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
    OtDocumentCodec codec = const OtDocumentCodec(),
  }) : _syncService = syncService,
       _noteId = noteId,
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
  final OtDocumentCodec _codec;

  late final DocumentProjectionApplier _applier;
  late final EditorOperationCapture _capture;

  int _confirmedRevision = 0;
  final List<OperationRequest> _pendingOps = [];
  Timer? _debounceTimer;

  final StreamController<List<PendingNoteOperationData>> _pendingOpsController =
      StreamController<List<PendingNoteOperationData>>.broadcast();

  Stream<List<PendingNoteOperationData>> get pendingOperationsStream =>
      _pendingOpsController.stream;

  int get confirmedRevision => _confirmedRevision;

  void Function(List<OperationRequest> ops)? onLocalOperations;

  bool _isComposing = false;
  _RebuildRequest? _pendingRebuild;

  void onCompositionStart() => _isComposing = true;
  void onCompositionEnd() {
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
    _capture.setSuppress(true);
    _capture.buildMirror();
    await _loadConfirmedState();
    _capture.start();
    await _hydrateFromServer();
    _capture.buildMirror();
    _capture.setSuppress(false);
  }

  Future<void> _loadConfirmedState() async {
    final doc = await _syncService.getConfirmedDocument(_noteId);
    if (doc != null) {
      _confirmedRevision = doc.revision;
    }
  }

  Future<void> _hydrateFromServer() async {
    try {
      final doc = await _syncService.getConfirmedDocument(_noteId);
      if (doc != null && doc.revision > 0) {
        final snapshot = jsonDecode(doc.documentJson) as Map<String, dynamic>;
        final pending = await _syncService.loadPendingProjection(_noteId);
        await _applier.rebuildFromSnapshot(
          snapshot: snapshot,
          pendingOps: pending,
          suppressCapture: () => _capture.setSuppress(true),
          resumeCapture: () => _capture.setSuppress(true),
          rebuildMirror: _capture.buildMirror,
        );
        _confirmedRevision = doc.revision;
      }
    } catch (e, stackTrace) {
      dev.log(
        'Hydration from server failed for note $_noteId',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _onOperationsCaptured(List<OperationRequestData> requests) {
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
    _scheduleDebounceFlush();
  }

  void _scheduleDebounceFlush() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 50), () {
      unawaited(_flushLocalOps());
    });
  }

  Future<void> _flushMutex = Future.value();

  Future<void> _flushLocalOps() async {
    if (_pendingOps.isEmpty) return;
    final ops = List<OperationRequest>.from(_pendingOps);
    _pendingOps.clear();

    final prevFlush = _flushMutex;
    final completer = Completer<void>();
    _flushMutex = completer.future;

    await prevFlush;
    try {
      final projectedCount = await _syncService
          .getProjectedOutboxOperationCount(_noteId);
      NoteSyncDebug.log(
        'adapter.flush.begin',
        noteId: _noteId,
        fields: {
          'confirmedRevision': _confirmedRevision,
          'projectedOutboxCount': projectedCount,
          'operationCount': ops.length,
        },
      );

      for (int i = 0; i < ops.length; i++) {
        final old = ops[i];
        ops[i] = OperationRequest(
          operationId: old.operationId,
          baseRevision: _confirmedRevision + projectedCount + i,
          kind: old.kind,
          blockId: old.blockId,
          payload: old.payload,
        );
      }

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
        await _syncService.enqueueOperation(_noteId, op);
      }

      onLocalOperations?.call(ops);
      final pending = await _syncService.getPendingOperations(_noteId);
      _pendingOpsController.add(pending);
    } finally {
      completer.complete();
    }
  }

  Future<void> flushNow() async {
    _debounceTimer?.cancel();
    if (_pendingOps.isNotEmpty) {
      unawaited(_flushLocalOps());
    }
    await _flushMutex;
  }

  Future<void> reconcile(SyncResult result) async {
    final canonical = result.canonicalDocument;
    if (canonical == null) return;
    _confirmedRevision = result.finalRevision;
    final rebasedOps = await _syncService.loadPendingProjection(_noteId);
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
    _debounceTimer?.cancel();
    _capture.stop();
    _pendingOpsController.close();
  }
}

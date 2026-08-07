import 'dart:async';
import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';
import 'package:supanotes/features/notes/editor/sync/note_session_handle.dart';
import 'package:supanotes/features/tasks/domain/task_projection_engine.dart';
import 'note_operation_adapter.dart';

class NoteSyncSession implements NoteEditorSyncHandle {
  final String noteId;
  final NoteOperationsSyncService syncService;
  final NoteOperationAdapter adapter;
  final TaskProjectionEngine? taskProjectionEngine;
  final MutableDocument document;
  final String userId;
  bool _captureLocalOperations;
  final void Function(Object error)? onTransientError;
  final void Function(Object error)? onProtocolError;

  Timer? _pollTimer;
  bool _isPolling = false;
  bool _disposed = false;
  bool _protocolFailed = false;
  bool _blockedByForeignSession = false;
  int _pendingSyncOperations = 0;
  Object? _lastError;
  Future<void> _projectionTail = Future<void>.value();
  Future<void> _syncTail = Future<void>.value();

  NoteSessionStatus _status = NoteSessionStatus.opening;
  @override
  NoteSessionStatus get status => _status;

  final StreamController<NoteSessionStatus> _statusController =
      StreamController<NoteSessionStatus>.broadcast();

  @override
  Stream<NoteSessionStatus> get statusChanges {
    late final StreamController<NoteSessionStatus> controller;
    late final StreamSubscription<NoteSessionStatus> subscription;
    controller = StreamController<NoteSessionStatus>.broadcast(
      onListen: () {
        controller.add(_status);
        subscription = _statusController.stream.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onCancel: () {
        subscription.cancel();
      },
    );
    return controller.stream;
  }

  void _setStatus(NoteSessionStatus newStatus) {
    if (_status == newStatus || _status == NoteSessionStatus.closed) return;
    _status = newStatus;
    _statusController.add(newStatus);
  }

  Object? get lastError => _lastError;
  @override
  bool get captureLocalOperations => _captureLocalOperations;

  NoteSyncSession({
    required this.noteId,
    required this.syncService,
    required this.document,
    required Editor editor,
    this.taskProjectionEngine,
    this.userId = '',
    bool captureLocalOperations = true,
    this.onTransientError,
    this.onProtocolError,
  }) : adapter = NoteOperationAdapter(
         document: document,
         syncService: syncService,
         noteId: noteId,
         editor: editor,
         captureLocalOperations: captureLocalOperations,
       ),
       _captureLocalOperations = captureLocalOperations;

  @override
  void setCaptureLocalOperations(bool captureLocalOperations) {
    if (_captureLocalOperations == captureLocalOperations) return;
    _captureLocalOperations = captureLocalOperations;
    adapter.setCaptureLocalOperations(captureLocalOperations);
  }

  @override
  Future<void> start() async {
    adapter.onLocalOperations = (_) {
      if (_captureLocalOperations) {
        unawaited(_enqueueProjection());
        unawaited(_onLocalOps());
      }
    };
    try {
      await adapter.start();
      _startPolling();
      if (_status == NoteSessionStatus.opening) {
        _setStatus(NoteSessionStatus.ready);
      }

      // The local document is ready now. Keep projection and network work in
      // the background so a large note or a slow connection cannot block the
      // first frame of the editor.
      unawaited(_enqueueProjection());
      if (_captureLocalOperations) {
        unawaited(_onLocalOps());
      }
    } catch (error, stackTrace) {
      _handleError(error, stackTrace, 'start');
      rethrow;
    }
  }

  Future<void> _enqueueProjection() {
    _projectionTail = _projectionTail.then((_) async {
      if (_disposed || taskProjectionEngine == null) return;
      try {
        await taskProjectionEngine!.projectTasksFromDocument(
          noteId: noteId,
          document: document,
          userId: userId,
        );
      } catch (error, stackTrace) {
        dev.log(
          'Task projection failed for $noteId',
          error: error,
          stackTrace: stackTrace,
        );
      }
    });
    return _projectionTail;
  }

  Future<void> _onLocalOps() async {
    if (_disposed) return;
    await _runSyncOperation('syncPending', () async {
      await _syncPending();
    });
  }

  Future<void> _syncPending() async {
    await syncService.syncPending(
      noteId,
      onReconcile: (result) async {
        await _handleSyncResult(result);
      },
    );
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      unawaited(pollNow());
    });
  }

  Future<void> pollNow() async {
    if (_disposed || _protocolFailed || _isPolling) return;
    _isPolling = true;
    try {
      await _runSyncOperation('pollNow', () async {
        if (_captureLocalOperations) {
          await _syncPending();
        }
        await syncService.pollAndReconcile(
          noteId,
          onReconcile: (result) async {
            await _handleSyncResult(result);
          },
        );
      });
    } finally {
      _isPolling = false;
    }
  }

  Future<void> _runSyncOperation(
    String context,
    Future<void> Function() operation,
  ) async {
    _pendingSyncOperations++;
    if (_pendingSyncOperations == 1 && _status != NoteSessionStatus.error) {
      _setStatus(NoteSessionStatus.syncing);
    }
    final run = _syncTail.then((_) async {
      try {
        if (_disposed || _protocolFailed) return;
        await operation();
        _lastError = null;
      } catch (error, stackTrace) {
        _handleError(error, stackTrace, context);
      } finally {
        _pendingSyncOperations--;
        if (_pendingSyncOperations == 0 &&
            !_disposed &&
            !_protocolFailed &&
            _lastError == null &&
            !_blockedByForeignSession &&
            _status != NoteSessionStatus.error) {
          _setStatus(NoteSessionStatus.ready);
        }
      }
    });
    _syncTail = run;
    await run;
  }

  Future<void> _handleSyncResult(SyncResult result) async {
    if (_disposed) return;
    if (result.isBlocked) {
      _blockedByForeignSession = true;
      _setStatus(NoteSessionStatus.blocked);
      return;
    }
    _blockedByForeignSession = false;
    if (result.canonicalDocument != null) {
      await adapter.reconcile(result);
      await _enqueueProjection();
    }
  }

  @override
  Future<void> flushNow() async {
    await adapter.flushNow();
    if (_captureLocalOperations) {
      await _onLocalOps();
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _setStatus(NoteSessionStatus.closing);
    _pollTimer?.cancel();
    try {
      // Persist the editor before waiting for a network request that may be
      // slow or unavailable. Closing must not discard an in-memory edit.
      await adapter.flushNow();
      await _projectionTail;
      // The outbox is durable now. Do not wait for the network queue during
      // teardown; the next session or catalog sync will retry it.
    } catch (error, stackTrace) {
      dev.log(
        'NoteSyncSession flush on dispose failed for $noteId',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      adapter.dispose();
      _setStatus(NoteSessionStatus.closed);
      unawaited(_statusController.close());
    }
  }

  void _handleError(Object error, StackTrace stackTrace, String context) {
    _lastError = error;
    dev.log(
      'NoteSyncSession $context failed for $noteId',
      error: error,
      stackTrace: stackTrace,
    );

    if (isProtocolError(error)) {
      if (error is NoteOperationsException && error.statusCode == 403) {
        setCaptureLocalOperations(false);
      }
      _protocolFailed = true;
      _pollTimer?.cancel();
      _setStatus(NoteSessionStatus.error);
      onProtocolError?.call(error);
    } else {
      _setStatus(NoteSessionStatus.syncError);
      onTransientError?.call(error);
    }
  }

  static bool isProtocolError(Object error) {
    if (error is FormatException || error is StateError) {
      return true;
    }
    if (error is NoteOperationsException) {
      final status = error.statusCode;
      if (status != null) {
        return status >= 400 && status < 500;
      }
      return error.errorCode != 'NETWORK_ERROR';
    }
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status != null && status >= 400 && status < 500) {
        return true;
      }
      return false;
    }
    return false;
  }
}

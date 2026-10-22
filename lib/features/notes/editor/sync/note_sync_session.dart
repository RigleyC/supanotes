import 'dart:async';
import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/notes/editor/sync/note_operation_adapter.dart';
import 'package:supanotes/features/notes/editor/sync/note_session_handle.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';
import 'package:super_editor/super_editor.dart';

class NoteSyncSession implements NoteEditorSyncHandle {
  NoteSyncSession({
    required this.noteId,
    required this.syncService,
    required this.document,
    required Editor editor,
    bool captureLocalOperations = true,
    this.networkCoalescingWindow = const Duration(milliseconds: 350),
    this.appLifecycleStates,
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

  final String noteId;
  final NoteOperationsSyncService syncService;
  final NoteOperationAdapter adapter;
  final MutableDocument document;
  final Duration networkCoalescingWindow;

  /// App-level lifecycle signal used to pause polling while the app is not in
  /// the foreground. Optional so sessions stay constructible without a binding.
  final Stream<AppLifecycleState>? appLifecycleStates;
  bool _captureLocalOperations;
  final void Function(Object error)? onTransientError;
  final void Function(Object error)? onProtocolError;

  static const _pollBaseInterval = Duration(seconds: 2);
  static const _pollMaxInterval = Duration(seconds: 30);

  Timer? _pollTimer;
  Timer? _networkSyncTimer;
  StreamSubscription<AppLifecycleState>? _lifecycleSubscription;
  Duration _pollInterval = _pollBaseInterval;
  bool _pollingEnabled = false;
  bool _pollingPaused = false;
  bool _isClosing = false;
  bool _isPolling = false;
  bool _disposed = false;
  bool _protocolFailed = false;
  bool _blockedByForeignSession = false;
  int _pendingSyncOperations = 0;
  Object? _lastError;
  Future<void> _reconcileTail = Future<void>.value();
  Future<void> _syncTail = Future<void>.value();

  NoteSessionStatus _status = NoteSessionStatus.opening;
  @override
  NoteSessionStatus get status => _status;

  final StreamController<NoteSessionStatus> _statusController =
      StreamController<NoteSessionStatus>.broadcast();
  final StreamController<bool> _captureController =
      StreamController<bool>.broadcast();

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

  @override
  bool get captureLocalOperations => _captureLocalOperations;

  @override
  Stream<bool> get captureLocalOperationsChanges => _captureController.stream;

  @override
  void setCaptureLocalOperations(bool captureLocalOperations) {
    if (_isClosing ||
        _disposed ||
        _captureLocalOperations == captureLocalOperations) {
      return;
    }
    _captureLocalOperations = captureLocalOperations;
    if (!captureLocalOperations) {
      _cancelScheduledNetworkSync();
    }
    adapter.setCaptureLocalOperations(captureLocalOperations);
    _captureController.add(captureLocalOperations);
  }

  @override
  Future<void> start() async {
    if (_isClosing || _disposed) return;
    adapter.onLocalOperations = _handleLocalOperations;
    try {
      await adapter.start();
      if (_isClosing || _disposed) return;
      _lifecycleSubscription = appLifecycleStates?.listen(
        _handleLifecycleState,
      );
      _startPolling();
      if (_status == NoteSessionStatus.opening) {
        _setStatus(NoteSessionStatus.ready);
      }

      // Startup keeps its eager retry semantics so a reopened note can clear
      // durable work immediately instead of waiting for the edit debounce.
      if (_captureLocalOperations) {
        unawaited(_onLocalOps());
      }
    } catch (error, stackTrace) {
      if (_isClosing || _disposed) return;
      _handleError(error, stackTrace, 'start');
      rethrow;
    }
  }

  void _handleLocalOperations(List<OperationRequest> _) {
    if (_isClosing || _disposed || !_captureLocalOperations) return;
    // A local edit is a strong signal that the open note is active, so the
    // next poll uses the base interval again.
    _pollInterval = _pollBaseInterval;
    _scheduleNetworkSync();
  }

  void _scheduleNetworkSync() {
    if (_isClosing || _disposed || _pollingPaused || !_captureLocalOperations) {
      return;
    }
    _networkSyncTimer?.cancel();
    _networkSyncTimer = Timer(networkCoalescingWindow, () {
      _networkSyncTimer = null;
      unawaited(_onLocalOps());
    });
  }

  void _cancelScheduledNetworkSync() {
    _networkSyncTimer?.cancel();
    _networkSyncTimer = null;
  }

  Future<void> _onLocalOps() async {
    if (_isClosing || _disposed) return;
    await _runSyncOperation('syncPending', () async {
      await _syncPending();
    });
  }

  Future<SyncResult> _syncPending() {
    return syncService.syncPending(
      noteId,
      onReconcile: (result) async {
        await _handleSyncResult(result);
      },
    );
  }

  void _startPolling() {
    _pollingEnabled = true;
    _scheduleNextPoll();
  }

  void _scheduleNextPoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_isClosing || _disposed || _protocolFailed || _pollingPaused) return;
    _pollTimer = Timer(_pollInterval, () {
      _pollTimer = null;
      unawaited(pollNow());
    });
  }

  void _handleLifecycleState(AppLifecycleState state) {
    if (_isClosing || _disposed) return;
    final shouldPause = state != AppLifecycleState.resumed;
    if (shouldPause == _pollingPaused) return;
    _pollingPaused = shouldPause;
    if (shouldPause) {
      _pollTimer?.cancel();
      _pollTimer = null;
      _cancelScheduledNetworkSync();
      return;
    }
    // Coming back to the foreground is the best moment to accept remote work,
    // so the first poll runs immediately and the cadence restarts at its base.
    _pollInterval = _pollBaseInterval;
    unawaited(pollNow());
  }

  void _updatePollInterval({required bool hasChanges}) {
    if (hasChanges) {
      _pollInterval = _pollBaseInterval;
      return;
    }
    if (_pollInterval >= _pollMaxInterval) return;
    final next = _pollInterval * 2;
    _pollInterval = next > _pollMaxInterval ? _pollMaxInterval : next;
  }

  Future<void> pollNow() async {
    if (_isClosing ||
        _disposed ||
        _protocolFailed ||
        _isPolling ||
        _pollingPaused) {
      return;
    }
    _isPolling = true;
    var hasChanges = false;
    try {
      // Polling is already an explicit network opportunity. Consume a pending
      // debounce so it cannot fire again immediately after this pass.
      _cancelScheduledNetworkSync();
      await _runSyncOperation('pollNow', () async {
        SyncResult? pendingResult;
        if (_captureLocalOperations) {
          pendingResult = await _syncPending();
        }
        final result = pendingResult;
        if (result?.hasReconciliationPayload ?? false) {
          hasChanges = true;
          return;
        }
        await syncService.pollAndReconcile(
          noteId,
          onReconcile: (result) async {
            hasChanges = true;
            await _handleSyncResult(result);
          },
        );
      });
    } finally {
      _isPolling = false;
      _updatePollInterval(hasChanges: hasChanges);
      if (_pollingEnabled) _scheduleNextPoll();
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
        if (_isClosing || _disposed || _protocolFailed) return;
        await operation();
        _lastError = null;
      } catch (error, stackTrace) {
        if (!_isClosing && !_disposed) {
          _handleError(error, stackTrace, context);
        }
      } finally {
        _pendingSyncOperations--;
        if (_pendingSyncOperations == 0 &&
            !_isClosing &&
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
    if (_isClosing || _disposed) return;
    if (result.isBlocked) {
      _blockedByForeignSession = true;
      _setStatus(NoteSessionStatus.blocked);
      return;
    }
    _blockedByForeignSession = false;
    if (result.canonicalDocument != null) {
      final reconcile = _reconcileTail.then<void>((_) async {
        if (_isClosing || _disposed) return;
        await adapter.reconcile(result);
        if (_isClosing || _disposed) return;
      });
      _reconcileTail = reconcile.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          dev.log(
            'Note reconciliation failed for $noteId',
            error: error,
            stackTrace: stackTrace,
          );
        },
      );
      await reconcile;
    }
  }

  @override
  Future<void> flushNow() async {
    if (_disposed) return;
    _cancelScheduledNetworkSync();
    await adapter.flushNow();
    // adapter.flushNow() may have emitted a freshly durable batch and thereby
    // scheduled the normal debounce. An explicit flush supersedes that timer.
    _cancelScheduledNetworkSync();
    if (_captureLocalOperations && !_isClosing) {
      // Local SQLite durability is the contract of flushNow. Remote ack is
      // intentionally outside the critical path; the session/outbox retries.
      unawaited(_onLocalOps());
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _isClosing = true;
    _setStatus(NoteSessionStatus.closing);
    final restartPollingOnFailure = _pollingEnabled;
    _pollingEnabled = false;
    _pollTimer?.cancel();
    _cancelScheduledNetworkSync();
    unawaited(_lifecycleSubscription?.cancel());
    adapter.setCaptureLocalOperations(false);
    adapter.onLocalOperations = null;
    try {
      // A sync response can already be reconciling locally when close starts.
      // Finish that local callback before the final flush.
      await _reconcileTail;
      // Persist the editor before waiting for a network request that may be
      // slow or unavailable. Closing must not discard an in-memory edit.
      await adapter.flushNow();
      // The outbox is durable now. Do not wait for the network queue during
      // teardown; the app-scoped outbox worker will retry it.
    } catch (error, stackTrace) {
      // The adapter still owns any operation that failed to reach the
      // durable outbox. Keep the session usable so the caller can retry the
      // close instead of losing that in-memory edit.
      _isClosing = false;
      _lastError = error;
      _setStatus(NoteSessionStatus.syncError);
      adapter.onLocalOperations = _handleLocalOperations;
      adapter.setCaptureLocalOperations(_captureLocalOperations);
      if (restartPollingOnFailure && !_protocolFailed) {
        _startPolling();
      }
      dev.log(
        'NoteSyncSession flush on dispose failed for $noteId',
        error: error,
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }

    _disposed = true;
    adapter.dispose();
    _setStatus(NoteSessionStatus.closed);
    unawaited(_statusController.close());
    unawaited(_captureController.close());
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
      _cancelScheduledNetworkSync();
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

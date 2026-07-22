import 'dart:async';
import 'dart:developer' as dev;
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/tasks/domain/task_projection_engine.dart';
import 'note_operation_adapter.dart';

class NoteSyncSession {
  static final Map<String, NoteSyncSession> _activeSessions = {};

  static bool isActive(String noteId) => _activeSessions.containsKey(noteId);

  final String noteId;
  final NoteOperationsSyncService syncService;
  final NoteOperationAdapter adapter;
  final TaskProjectionEngine? taskProjectionEngine;
  final MutableDocument document;
  final String userId;

  Timer? _pollTimer;
  bool _isPolling = false;
  bool _disposed = false;

  NoteSyncSession({
    required this.noteId,
    required this.syncService,
    required this.document,
    required Editor editor,
    this.taskProjectionEngine,
    this.userId = '',
  }) : adapter = NoteOperationAdapter(
         document: document,
         syncService: syncService,
         noteId: noteId,
         editor: editor,
       );

  Future<void> start() async {
    _activeSessions[noteId] = this;
    adapter.onLocalOperations = (_) {
      unawaited(_triggerLocalProjection());
      unawaited(_onLocalOps());
    };
    try {
      await adapter.start();
      await _triggerLocalProjection();
      // Drain operations persisted by an earlier offline session before polling.
      await _onLocalOps();
      _startPolling();
    } catch (_) {
      if (_activeSessions[noteId] == this) {
        _activeSessions.remove(noteId);
      }
      rethrow;
    }
  }

  Future<void> _triggerLocalProjection() async {
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
  }

  Future<void> _onLocalOps() async {
    if (_disposed) return;
    try {
      await syncService.syncPending(
        noteId,
        onReconcile: (result) async {
          if (!_disposed && result.canonicalDocument != null) {
            await adapter.reconcile(result);
            await _triggerLocalProjection();
          }
        },
      );
    } catch (error, stackTrace) {
      dev.log(
        'NoteSyncSession sync failed for $noteId',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_disposed || _isPolling) return;
      _isPolling = true;
      try {
        // Retry the persistent outbox after connectivity is restored.
        await _onLocalOps();
        await syncService.pollAndReconcile(
          noteId,
          onReconcile: (result) async {
            if (!_disposed && result.canonicalDocument != null) {
              await adapter.reconcile(result);
              await _triggerLocalProjection();
            }
          },
        );
      } catch (error, stackTrace) {
        dev.log(
          'NoteSyncSession poll failed for $noteId',
          error: error,
          stackTrace: stackTrace,
        );
      } finally {
        _isPolling = false;
      }
    });
  }

  Future<void> flushNow() async {
    await adapter.flushNow();
    await _onLocalOps();
  }

  Future<void> dispose() async {
    _disposed = true;
    if (_activeSessions[noteId] == this) {
      _activeSessions.remove(noteId);
    }
    _pollTimer?.cancel();
    try {
      await adapter.flushNow();
      await syncService.syncPending(
        noteId,
        onReconcile: (result) async {
          if (!_disposed && result.canonicalDocument != null) {
            await adapter.reconcile(result);
            await _triggerLocalProjection();
          }
        },
      );
    } catch (error, stackTrace) {
      dev.log(
        'NoteSyncSession flush on dispose failed for $noteId',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      adapter.dispose();
    }
  }
}

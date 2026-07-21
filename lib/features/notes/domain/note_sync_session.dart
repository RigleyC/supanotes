import 'dart:async';
import 'dart:developer' as dev;
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'note_operation_adapter.dart';

class NoteSyncSession {
  final String noteId;
  final NoteOperationsSyncService syncService;
  final NoteOperationAdapter adapter;

  Timer? _pollTimer;
  bool _isPolling = false;
  bool _disposed = false;

  NoteSyncSession({
    required this.noteId,
    required this.syncService,
    required MutableDocument document,
    required Editor editor,
  }) : adapter = NoteOperationAdapter(
          document: document,
          syncService: syncService,
          noteId: noteId,
          editor: editor,
        );

  Future<void> start() async {
    adapter.onLocalOperations = (_) {
      unawaited(_onLocalOps());
    };

    await adapter.start();
    _startPolling();
  }

  Future<void> _onLocalOps() async {
    if (_disposed) return;
    try {
      await syncService.syncPending(
        noteId,
        onReconcile: (result) async {
          if (!_disposed && result.canonicalDocument != null) {
            await adapter.reconcile(result);
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
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_disposed || _isPolling) return;
      _isPolling = true;
      try {
        await syncService.pollAndReconcile(
          noteId,
          onReconcile: (result) async {
            if (!_disposed && result.canonicalDocument != null) {
              await adapter.reconcile(result);
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
  }

  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    adapter.dispose();
  }
}

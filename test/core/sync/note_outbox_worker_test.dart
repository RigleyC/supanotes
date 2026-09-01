import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/core/sync/note_outbox_worker.dart';

void main() {
  test('drains inactive notes with pending operations', () async {
    final calls = <String>[];
    final worker = NoteOutboxWorker(
      loadPendingNoteIds: () async => ['note-a', 'note-b'],
      syncNote: (noteId) async {
        calls.add(noteId);
        return SyncResult.empty();
      },
      isNoteActive: (_) => false,
    );
    addTearDown(worker.dispose);

    await worker.drain();

    expect(calls, ['note-a', 'note-b']);
  });

  test('skips notes that are active in an editor session', () async {
    final calls = <String>[];
    final worker = NoteOutboxWorker(
      loadPendingNoteIds: () async => ['active', 'closed'],
      syncNote: (noteId) async {
        calls.add(noteId);
        return SyncResult.empty();
      },
      isNoteActive: (noteId) => noteId == 'active',
    );
    addTearDown(worker.dispose);

    await worker.drain();

    expect(calls, ['closed']);
  });

  test('a transient failure does not block another note', () async {
    final calls = <String>[];
    final worker = NoteOutboxWorker(
      loadPendingNoteIds: () async => ['offline', 'healthy'],
      syncNote: (noteId) async {
        calls.add(noteId);
        if (noteId == 'offline') throw Exception('network unavailable');
        return SyncResult.empty();
      },
      isNoteActive: (_) => false,
      backoffForAttempt: (_) => const Duration(minutes: 1),
    );
    addTearDown(worker.dispose);

    await worker.drain();

    expect(calls, ['offline', 'healthy']);
  });

  test('transient failures respect backoff before retrying', () async {
    var now = DateTime.utc(2026, 9, 1, 12);
    var attempts = 0;
    final worker = NoteOutboxWorker(
      loadPendingNoteIds: () async => ['note-a'],
      syncNote: (_) async {
        attempts++;
        if (attempts == 1) throw Exception('offline');
        return SyncResult.empty();
      },
      isNoteActive: (_) => false,
      now: () => now,
      backoffForAttempt: (_) => const Duration(seconds: 1),
    );
    addTearDown(worker.dispose);

    await worker.drain();
    await worker.drain();
    expect(attempts, 1);

    now = now.add(const Duration(seconds: 1));
    await worker.drain();
    expect(attempts, 2);
  });

  test('concurrent drain requests never sync the same pass concurrently', () async {
    final firstSyncStarted = Completer<void>();
    final releaseFirstSync = Completer<void>();
    var inFlight = 0;
    var maxInFlight = 0;
    var calls = 0;

    final worker = NoteOutboxWorker(
      loadPendingNoteIds: () async => ['note-a'],
      syncNote: (_) async {
        calls++;
        inFlight++;
        if (inFlight > maxInFlight) maxInFlight = inFlight;
        if (calls == 1) {
          firstSyncStarted.complete();
          await releaseFirstSync.future;
        }
        inFlight--;
        return SyncResult.empty();
      },
      isNoteActive: (_) => false,
    );
    addTearDown(worker.dispose);

    final first = worker.drain();
    await firstSyncStarted.future;
    final second = worker.drain();
    releaseFirstSync.complete();
    await Future.wait([first, second]);

    expect(maxInFlight, 1);
  });
}

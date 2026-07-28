import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/domain/note_session_activity_tracker.dart';
import 'package:supanotes/features/notes/domain/note_session_coordinator.dart';

void main() {
  group('NoteSessionCoordinator', () {
    test('reuses the same pending session for duplicate opens', () async {
      final tracker = NoteSessionActivityTracker();
      final coordinator = NoteSessionCoordinator<_FakeSessionHandle>(
        activityTracker: tracker,
      );
      final start = Completer<void>();
      var created = 0;

      final first = coordinator.open('note-1', () {
        created++;
        return _FakeSessionHandle(startCompleter: start);
      });
      final second = coordinator.open('note-1', () {
        created++;
        return _FakeSessionHandle();
      });

      expect(created, 1);
      expect(coordinator.statusOf('note-1'), NoteSessionStatus.opening);
      expect(tracker.isActive('note-1'), isTrue);

      start.complete();
      expect(identical(await first, await second), isTrue);
      expect(coordinator.statusOf('note-1'), NoteSessionStatus.ready);

      await coordinator.close('note-1');
      expect(tracker.isActive('note-1'), isFalse);
    });

    test('reuses a ready session for duplicate opens', () async {
      final coordinator = NoteSessionCoordinator<_FakeSessionHandle>();
      var created = 0;

      final first = await coordinator.open('note-1', () {
        created++;
        return _FakeSessionHandle();
      });
      final second = await coordinator.open('note-1', () {
        created++;
        return _FakeSessionHandle();
      });

      expect(created, 1);
      expect(identical(first, second), isTrue);
      expect(first.status, NoteSessionStatus.ready);
    });

    test('waits for closing before reopening the same note', () async {
      final coordinator = NoteSessionCoordinator<_FakeSessionHandle>();
      final dispose = Completer<void>();
      var created = 0;

      final first = await coordinator.open('note-1', () {
        created++;
        return _FakeSessionHandle(disposeCompleter: dispose);
      });

      final closeFuture = coordinator.close('note-1');

      var reopened = false;
      final reopenFuture = coordinator.open('note-1', () {
        reopened = true;
        created++;
        return _FakeSessionHandle();
      });

      await Future<void>.delayed(Duration.zero);
      expect(reopened, isFalse);

      dispose.complete();
      await closeFuture;
      final second = await reopenFuture;

      expect(created, 2);
      expect(identical(first, second), isFalse);
      expect(second.status, NoteSessionStatus.ready);
    });

    test('exposes syncing and returns to ready after a flush', () async {
      final coordinator = NoteSessionCoordinator<_FakeSessionHandle>();
      final flush = Completer<void>();
      final session = await coordinator.open(
        'note-1',
        () => _FakeSessionHandle(flushCompleter: flush),
      );

      final flushFuture = session.flushNow();
      expect(session.status, NoteSessionStatus.syncing);

      flush.complete();
      await flushFuture;
      expect(session.status, NoteSessionStatus.ready);
    });

    test('shares repeated close calls and disposes once', () async {
      final coordinator = NoteSessionCoordinator<_FakeSessionHandle>();
      final dispose = Completer<void>();
      final handle = _FakeSessionHandle(disposeCompleter: dispose);
      final session = await coordinator.open('note-1', () => handle);

      final firstClose = coordinator.close('note-1');
      final secondClose = coordinator.close('note-1');

      dispose.complete();
      await Future.wait([firstClose, secondClose]);

      expect(handle.disposeCalls, 1);
      expect(session.status, NoteSessionStatus.closed);
      expect(coordinator.statusOf('note-1'), NoteSessionStatus.closed);
    });

    test('cancels opening and disposes resources if close() is called during async open()', () async {
      final coordinator = NoteSessionCoordinator<_FakeSessionHandle>();
      final start = Completer<void>();
      final handle = _FakeSessionHandle(startCompleter: start);

      final openFuture = coordinator.open('note-1', () => handle);
      final closeFuture = coordinator.close('note-1');

      start.complete();

      await closeFuture;
      expect(openFuture, throwsStateError);
      expect(handle.disposeCalls, 1);
      expect(coordinator.statusOf('note-1'), NoteSessionStatus.closed);
    });

    test('rolls back created resources when opening fails', () async {
      final coordinator = NoteSessionCoordinator<_FakeSessionHandle>();
      final handle = _FakeSessionHandle(failStart: true);

      await expectLater(
        coordinator.open('note-1', () => handle),
        throwsStateError,
      );

      expect(handle.disposeCalls, 1);
      expect(coordinator.statusOf('note-1'), NoteSessionStatus.closed);
    });

    test('snapshots active sessions', () async {
      final coordinator = NoteSessionCoordinator<_FakeSessionHandle>();
      await coordinator.open('note-1', () => _FakeSessionHandle());

      final snap = coordinator.snapshot();
      expect(snap.activeCount, 1);
      expect(snap.sessionsByStatus[NoteSessionStatus.ready], 1);
    });

    test(
      'statusOf, statusChangesOf, and snapshot agree during opening',
      () async {
        final coordinator = NoteSessionCoordinator<_FakeSessionHandle>();
        final startCompleter = Completer<void>();

        unawaited(
          coordinator.open(
            'note-opening',
            () => _FakeSessionHandle(startCompleter: startCompleter),
          ),
        );

        expect(coordinator.statusOf('note-opening'), NoteSessionStatus.opening);

        final initialStreamStatus =
            await coordinator.statusChangesOf('note-opening').first;
        expect(initialStreamStatus, NoteSessionStatus.opening);

        final snap = coordinator.snapshot();
        expect(snap.sessionsByStatus[NoteSessionStatus.opening], 1);

        startCompleter.complete();
      },
    );
  });
}

class _FakeSessionHandle implements NoteSessionHandle {
  _FakeSessionHandle({
    this.startCompleter,
    this.flushCompleter,
    this.disposeCompleter,
    this.failStart = false,
  });

  final Completer<void>? startCompleter;
  final Completer<void>? flushCompleter;
  final Completer<void>? disposeCompleter;
  final bool failStart;

  int startCalls = 0;
  int flushCalls = 0;
  int disposeCalls = 0;

  NoteSessionStatus _status = NoteSessionStatus.opening;
  @override
  NoteSessionStatus get status => _status;

  final StreamController<NoteSessionStatus> _statusController =
      StreamController<NoteSessionStatus>.broadcast();

  @override
  Stream<NoteSessionStatus> get statusChanges => _statusController.stream;

  void setStatus(NoteSessionStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  @override
  Future<void> start() async {
    startCalls++;
    await startCompleter?.future;
    if (failStart) {
      _status = NoteSessionStatus.error;
      throw StateError('start failed');
    }
    _status = NoteSessionStatus.ready;
  }

  @override
  Future<void> flushNow() async {
    flushCalls++;
    _status = NoteSessionStatus.syncing;
    await flushCompleter?.future;
    _status = NoteSessionStatus.ready;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    _status = NoteSessionStatus.closed;
    await disposeCompleter?.future;
  }
}

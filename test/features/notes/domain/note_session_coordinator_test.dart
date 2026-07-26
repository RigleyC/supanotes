import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/domain/note_session_coordinator.dart';

void main() {
  group('NoteSessionCoordinator', () {
    test('reuses the same pending session for duplicate opens', () async {
      final coordinator = NoteSessionCoordinator<_FakeSessionHandle>();
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

      start.complete();
      expect(identical(await first, await second), isTrue);
      expect(coordinator.statusOf('note-1'), NoteSessionStatus.ready);
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
      expect(first.status, NoteSessionStatus.closing);

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

      expect(session.status, NoteSessionStatus.closing);
      dispose.complete();
      await Future.wait([firstClose, secondClose]);

      expect(handle.disposeCalls, 1);
      expect(session.status, NoteSessionStatus.closed);
      expect(coordinator.statusOf('note-1'), NoteSessionStatus.closed);
    });

    test('rejects mutations after closing starts', () async {
      final coordinator = NoteSessionCoordinator<_FakeSessionHandle>();
      final dispose = Completer<void>();
      final session = await coordinator.open(
        'note-1',
        () => _FakeSessionHandle(disposeCompleter: dispose),
      );

      final closeFuture = coordinator.close('note-1');

      expect(session.status, NoteSessionStatus.closing);
      expect(session.flushNow, throwsStateError);

      dispose.complete();
      await closeFuture;
    });

    test('rolls back created resources when opening fails', () async {
      final coordinator = NoteSessionCoordinator<_FakeSessionHandle>();
      final handle = _FakeSessionHandle(failStart: true);

      await expectLater(
        coordinator.open('note-1', () => handle),
        throwsStateError,
      );

      expect(handle.disposeCalls, 1);
      expect(coordinator.statusOf('note-1'), NoteSessionStatus.error);

      final recovered = await coordinator.open(
        'note-1',
        () => _FakeSessionHandle(),
      );
      expect(recovered.status, NoteSessionStatus.ready);
    });

    test('does not let stale close results replace a newer session', () async {
      final coordinator = NoteSessionCoordinator<_FakeSessionHandle>();
      final first = await coordinator.open(
        'note-1',
        () => _FakeSessionHandle(),
      );

      await coordinator.close('note-1');
      final second = await coordinator.open(
        'note-1',
        () => _FakeSessionHandle(),
      );

      expect(first.status, NoteSessionStatus.closed);
      expect(second.status, NoteSessionStatus.ready);
      expect(coordinator.statusOf('note-1'), NoteSessionStatus.ready);
    });
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

  @override
  Future<void> start() async {
    startCalls++;
    await startCompleter?.future;
    if (failStart) {
      throw StateError('start failed');
    }
  }

  @override
  Future<void> flushNow() async {
    flushCalls++;
    await flushCompleter?.future;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await disposeCompleter?.future;
  }
}

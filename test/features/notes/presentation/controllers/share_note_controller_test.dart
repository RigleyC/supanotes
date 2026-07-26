import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/data/shares_repository.dart';
import 'package:supanotes/features/notes/domain/share_model.dart';
import 'package:supanotes/features/notes/domain/share_permission.dart';
import 'package:supanotes/features/notes/presentation/controllers/share_list_controller.dart';
import 'package:supanotes/features/notes/presentation/controllers/share_note_controller.dart';

void main() {
  test('simultaneous share operations are isolated by note', () async {
    final repo = _FakeSharesRepository();
    final noteA = Completer<void>();
    final noteB = Completer<void>();
    repo.shareCompleters['note-a'] = noteA;
    repo.shareCompleters['note-b'] = noteB;

    final container = ProviderContainer(
      overrides: [sharesRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final noteAProvider = shareNoteControllerProvider('note-a');
    final noteBProvider = shareNoteControllerProvider('note-b');
    final noteASubscription = container.listen(noteAProvider, (_, _) {});
    final noteBSubscription = container.listen(noteBProvider, (_, _) {});
    addTearDown(noteASubscription.close);
    addTearDown(noteBSubscription.close);

    final futureA = container
        .read(noteAProvider.notifier)
        .share(email: 'a@example.com', permission: SharePermission.view);
    final futureB = container
        .read(noteBProvider.notifier)
        .share(email: 'b@example.com', permission: SharePermission.edit);
    await pumpEventQueue();

    expect(container.read(noteAProvider).isLoading, isTrue);
    expect(container.read(noteBProvider).isLoading, isTrue);

    noteA.complete();
    await futureA;

    expect(container.read(noteAProvider).hasValue, isTrue);
    expect(container.read(noteBProvider).isLoading, isTrue);

    noteB.completeError(StateError('note b failed'));
    await futureB;

    expect(container.read(noteAProvider).hasValue, isTrue);
    expect(container.read(noteBProvider).hasError, isTrue);
    expect(repo.shareCalls.map((call) => call.noteId), ['note-a', 'note-b']);
  });

  test(
    'older operation result does not replace newer result for same note',
    () async {
      final repo = _FakeSharesRepository();
      final first = Completer<void>();
      repo.shareQueue.add(first);

      final container = ProviderContainer(
        overrides: [sharesRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      final provider = shareNoteControllerProvider('note-a');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);

      final controller = container.read(provider.notifier);
      final firstFuture = controller.share(
        email: 'first@example.com',
        permission: SharePermission.view,
      );
      await pumpEventQueue();

      final secondFuture = controller.share(
        email: 'second@example.com',
        permission: SharePermission.edit,
      );
      await secondFuture;

      expect(container.read(provider).hasValue, isTrue);

      first.completeError(StateError('old failed'));
      await firstFuture;

      final state = container.read(provider);
      expect(state.hasValue, isTrue);
      expect(state.hasError, isFalse);
    },
  );

  test('list invalidation can target only the affected note', () async {
    final repo = _FakeSharesRepository();
    final container = ProviderContainer(
      overrides: [sharesRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    await container.read(shareListProvider('note-a').future);
    await container.read(shareListProvider('note-b').future);
    expect(repo.listCalls, ['note-a', 'note-b']);

    container.invalidate(shareListProvider('note-a'));
    await container.read(shareListProvider('note-a').future);

    expect(repo.listCalls, ['note-a', 'note-b', 'note-a']);
  });
}

class _FakeSharesRepository implements SharesRepository {
  final shareCalls =
      <({String noteId, String email, SharePermission permission})>[];
  final listCalls = <String>[];
  final shareCompleters = <String, Completer<void>>{};
  final shareQueue = <Completer<void>>[];

  @override
  Future<void> shareNote({
    required String noteId,
    required String email,
    required SharePermission permission,
  }) async {
    shareCalls.add((noteId: noteId, email: email, permission: permission));
    if (shareQueue.isNotEmpty) {
      await shareQueue.removeAt(0).future;
      return;
    }
    final completer = shareCompleters[noteId];
    if (completer != null) {
      await completer.future;
    }
  }

  @override
  Future<void> deleteShare({
    required String noteId,
    required String userId,
  }) async {}

  @override
  Future<List<ShareModel>> listShares({required String noteId}) async {
    listCalls.add(noteId);
    return [];
  }
}

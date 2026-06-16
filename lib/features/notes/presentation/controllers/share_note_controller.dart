import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/shares_repository.dart';

/// Controller that exposes the one-shot share request as an [AsyncValue].
///
/// The UI watches this state to render loading / error / success feedback
/// instead of tracking a local `isLoading` flag.
final shareNoteControllerProvider =
    NotifierProvider.autoDispose<ShareNoteController, AsyncValue<void>>(
  ShareNoteController.new,
);

class ShareNoteController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> share({
    required String noteId,
    required String email,
    required String permission,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(sharesRepositoryProvider).shareNote(
            noteId: noteId,
            email: email,
            permission: permission,
          );
    });
  }
}

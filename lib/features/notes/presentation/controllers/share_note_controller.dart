import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/shares_repository.dart';
import '../../domain/share_permission.dart';

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
    required SharePermission permission,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(sharesRepositoryProvider).shareNote(
            noteId: noteId,
            email: email,
            permission: permission,
          ),
    );
  }
}

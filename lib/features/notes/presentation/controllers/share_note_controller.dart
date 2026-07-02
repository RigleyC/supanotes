import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/shares_repository.dart';
import '../../domain/share_permission.dart';

final shareNoteControllerProvider =
    AsyncNotifierProvider.autoDispose<ShareNoteController, void>(
      ShareNoteController.new,
    );

class ShareNoteController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> share({
    required String noteId,
    required String email,
    required SharePermission permission,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref
          .read(sharesRepositoryProvider)
          .shareNote(noteId: noteId, email: email, permission: permission),
    );
  }

  Future<void> revoke({required String noteId, required String userId}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref
          .read(sharesRepositoryProvider)
          .deleteShare(noteId: noteId, userId: userId),
    );
  }
}
